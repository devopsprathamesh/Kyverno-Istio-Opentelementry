#!/usr/bin/env bash
# Runtime validation. Usage: validate-installation.sh [SCOPE]
# SCOPE one of: all (default) | prometheus | grafana | jaeger | loki |
# collector | operator | e2e
#
# `make validate-prometheus` etc. call this with SCOPE set — this is
# the same "one script, scope argument" pattern already used by
# istio/kyverno's clean.sh, so the required scripts/ directory listing
# doesn't need a dozen near-duplicate per-tool files.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=./lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

SCOPE="${1:-all}"
FAIL_COUNT=0
pass() { log_pass "$1"; }
warn() { log_warn "$1"; }
fail() { log_fail "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if ! kube_reachable; then
  log_info "No reachable cluster — validate-installation skipped."
  exit 0
fi

# A local port-forward + trap-cleanup, reused by every check below that
# needs to talk to a backend's HTTP API from outside the cluster.
_PF_PIDS=()
cleanup() {
  for pid in "${_PF_PIDS[@]:-}"; do kill "${pid}" >/dev/null 2>&1 || true; done
}
trap cleanup EXIT

start_port_forward() {
  local svc="$1" ns="$2" local_port="$3" remote_port="$4"
  kubectl -n "${ns}" port-forward "svc/${svc}" "${local_port}:${remote_port}" >/dev/null 2>&1 &
  _PF_PIDS+=("$!")
  sleep 2
}

validate_operator() {
  log_section "Operator validation"
  crd_exists opentelemetrycollectors.opentelemetry.io && pass "CRD opentelemetrycollectors.opentelemetry.io exists" || fail "CRD opentelemetrycollectors.opentelemetry.io missing"
  crd_exists instrumentations.opentelemetry.io && pass "CRD instrumentations.opentelemetry.io exists" || fail "CRD instrumentations.opentelemetry.io missing"
  deployment_rollout_ready "${OPENTELEMETRY_NAMESPACE}" opentelemetry-operator 5 && pass "Operator Deployment Ready" || fail "Operator Deployment not Ready"
  any_webhook_exists mutating opentelemetry-operator-mutation && pass "Operator mutating webhook registered" || fail "Operator mutating webhook not found"
}

validate_prometheus() {
  log_section "Prometheus validation"
  deployment_rollout_ready "${OBSERVABILITY_NAMESPACE}" kube-prometheus-stack-operator 5 && pass "Prometheus Operator Deployment Ready" || fail "Prometheus Operator Deployment not Ready"
  resource_exists statefulset prometheus-kube-prometheus-stack-prometheus "${OBSERVABILITY_NAMESPACE}" && pass "Prometheus StatefulSet exists" || fail "Prometheus StatefulSet missing"
  start_port_forward "${PROMETHEUS_SERVICE}" "${OBSERVABILITY_NAMESPACE}" 19090 "${PROMETHEUS_PORT}"
  if prometheus_query_has_result 19090 "up"; then pass "Prometheus query API works ('up' returns results)"; else fail "Prometheus query API did not return results for 'up'"; fi
  if prometheus_target_healthy 19090 "kube-state-metrics"; then pass "kube-state-metrics target healthy"; else warn "kube-state-metrics target not confirmed healthy yet"; fi
  resource_exists prometheusrule observability-recording-rules "${OBSERVABILITY_NAMESPACE}" 2>/dev/null && pass "Recording rules loaded" || warn "Recording rules PrometheusRule not found yet"
  resource_exists prometheusrule observability-alerts "${OBSERVABILITY_NAMESPACE}" 2>/dev/null && pass "Alerting rules loaded" || warn "Alerting rules PrometheusRule not found yet"
}

validate_grafana() {
  log_section "Grafana validation"
  deployment_rollout_ready "${OBSERVABILITY_NAMESPACE}" grafana 5 && pass "Grafana Deployment Ready" || fail "Grafana Deployment not Ready"
  start_port_forward "${GRAFANA_SERVICE}" "${OBSERVABILITY_NAMESPACE}" 13000 "${GRAFANA_PORT}"
  if grafana_healthy 13000; then pass "Grafana health endpoint OK"; else fail "Grafana health endpoint not OK"; fi
  if [ -f "${GENERATED_DIR}/grafana-admin-password" ]; then
    local pass_val; pass_val="$(cat "${GENERATED_DIR}/grafana-admin-password")"
    for ds in prometheus jaeger loki; do
      if grafana_datasource_healthy 13000 "${ds}" "${GRAFANA_LAB_DEFAULT_USER}" "${pass_val}"; then
        pass "Grafana datasource '${ds}' healthy"
      else
        warn "Grafana datasource '${ds}' not confirmed healthy (backend may still be starting)"
      fi
    done
  else
    warn "No generated admin password found — skipping datasource-health checks (run install-grafana.sh first)."
  fi
  resource_exists configmap grafana-dashboards-provisioning "${OBSERVABILITY_NAMESPACE}" && pass "Dashboards ConfigMap provisioned" || fail "Dashboards ConfigMap missing"
}

validate_jaeger() {
  log_section "Jaeger validation"
  deployment_rollout_ready "${OBSERVABILITY_NAMESPACE}" jaeger 5 && pass "Jaeger Deployment Ready" || fail "Jaeger Deployment not Ready"
  start_port_forward "${JAEGER_QUERY_SERVICE}" "${OBSERVABILITY_NAMESPACE}" 16686 "${JAEGER_QUERY_PORT}"
  if curl -fsS -o /dev/null "http://127.0.0.1:16686/" 2>/dev/null; then pass "Jaeger Query UI reachable"; else fail "Jaeger Query UI not reachable"; fi
  start_port_forward "${JAEGER_COLLECTOR_OTLP_GRPC_SERVICE}" "${OBSERVABILITY_NAMESPACE}" 14318 "${JAEGER_OTLP_HTTP_PORT}"
  local trace_id; trace_id="$(send_test_otlp_trace 14318 validate-installation-probe 2>/dev/null || true)"
  if [ -n "${trace_id}" ]; then
    sleep 3
    if jaeger_has_traces_for_service 16686 validate-installation-probe; then pass "Test trace searchable in Jaeger (trace_id=${trace_id})"; else warn "Test trace sent but not yet searchable — Jaeger may still be indexing"; fi
  else
    warn "Could not send a test OTLP trace directly to Jaeger."
  fi
}

validate_loki() {
  log_section "Loki validation"
  if deployment_rollout_ready "${OBSERVABILITY_NAMESPACE}" loki 5 2>/dev/null || resource_exists statefulset loki "${OBSERVABILITY_NAMESPACE}"; then
    pass "Loki workload exists"
  else
    fail "Loki workload missing"
  fi
  start_port_forward "${LOKI_SERVICE}" "${OBSERVABILITY_NAMESPACE}" 13100 "${LOKI_PORT}"
  if curl -fsS -o /dev/null "http://127.0.0.1:13100/ready" 2>/dev/null; then pass "Loki readiness endpoint OK"; else fail "Loki readiness endpoint not OK"; fi
  send_test_otlp_log 13100 validate-installation-probe "validate-installation test log" >/dev/null 2>&1 || warn "Could not send a test OTLP log directly to Loki (note: Loki's OTLP endpoint is proxied at /otlp, not the bare Loki port in some chart configs — see docs/06-logs.md)."
}

validate_collector() {
  log_section "Collector validation"
  daemonset_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-agent && pass "Collector Agent DaemonSet Ready on all nodes" || fail "Collector Agent DaemonSet not Ready"
  deployment_rollout_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-gateway 5 && pass "Collector Gateway Deployment Ready" || fail "Collector Gateway Deployment not Ready"
  start_port_forward "${COLLECTOR_GATEWAY_SERVICE}" "${OPENTELEMETRY_NAMESPACE}" 13133 "${COLLECTOR_HEALTH_CHECK_PORT}"
  if collector_health_check 13133; then pass "Collector Gateway health_check extension OK"; else fail "Collector Gateway health_check extension not OK"; fi
  start_port_forward "${COLLECTOR_GATEWAY_SERVICE}" "${OPENTELEMETRY_NAMESPACE}" 18888 "${COLLECTOR_INTERNAL_METRICS_PORT}"
  if [ -n "$(collector_internal_metric 18888 otelcol_receiver_accepted)" ]; then pass "Collector internal metrics available"; else warn "Collector internal metrics endpoint returned nothing yet"; fi
}

validate_e2e() {
  log_section "End-to-end telemetry validation (requires deploy-demo to have run)"
  if ! namespace_exists "${OTEL_DEMO_NAMESPACE}"; then
    warn "Demo namespace '${OTEL_DEMO_NAMESPACE}' not found — skipping end-to-end checks. Run 'make deploy-demo' first."
    return 0
  fi
  deployment_rollout_ready "${OTEL_DEMO_NAMESPACE}" frontend 5 && pass "Demo frontend Deployment Ready" || warn "Demo frontend not Ready yet"
}

case "${SCOPE}" in
  operator) validate_operator ;;
  prometheus) validate_prometheus ;;
  grafana) validate_grafana ;;
  jaeger) validate_jaeger ;;
  loki) validate_loki ;;
  collector) validate_collector ;;
  e2e) validate_e2e ;;
  all)
    validate_operator
    validate_prometheus
    validate_jaeger
    validate_loki
    validate_collector
    validate_grafana
    validate_e2e
    ;;
  *) log_fatal "Unknown scope '${SCOPE}'. Valid: all|operator|prometheus|grafana|jaeger|loki|collector|e2e" ;;
esac

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "validate-installation (scope=${SCOPE}): ${FAIL_COUNT} mandatory check(s) failed."
  exit 1
fi
log_pass "validate-installation (scope=${SCOPE}): all mandatory checks passed."
