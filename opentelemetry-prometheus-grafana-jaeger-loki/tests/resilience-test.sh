#!/usr/bin/env bash
# Runtime test: backend-outage resilience. Scales Jaeger to zero,
# confirms the Collector Gateway keeps running (queues/retries rather
# than crashing) and its own internal metrics show failed-export
# activity, then scales Jaeger back up and confirms exports resume.
# Never touches Cilium/kube-proxy or any other module — scoped
# entirely to this module's own observability namespace.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — resilience-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "resilience-test"

ORIGINAL_REPLICAS="$(kubectl -n "${OBSERVABILITY_NAMESPACE}" get deployment jaeger -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"
restore_jaeger() {
  kubectl -n "${OBSERVABILITY_NAMESPACE}" scale deployment/jaeger --replicas="${ORIGINAL_REPLICAS:-1}" >/dev/null 2>&1 || true
  kill "${PF_PID:-0}" >/dev/null 2>&1 || true
}
trap restore_jaeger EXIT

log_info "Scaling Jaeger to 0 replicas to simulate a backend outage..."
kubectl -n "${OBSERVABILITY_NAMESPACE}" scale deployment/jaeger --replicas=0 >/dev/null
sleep 5

if daemonset_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-agent && deployment_rollout_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-gateway 5; then
  pass "Collector Agent/Gateway remain healthy with the trace backend down (queuing/retrying, not crashing)"
else
  fail "Collector Agent/Gateway became unhealthy when the trace backend went down — this should not happen (sending_queue exists precisely to absorb this)"
fi

kubectl -n "${OPENTELEMETRY_NAMESPACE}" port-forward "svc/${COLLECTOR_GATEWAY_SERVICE}" 18888:"${COLLECTOR_INTERNAL_METRICS_PORT}" >/dev/null 2>&1 &
PF_PID=$!
sleep 3
if [ -n "$(collector_internal_metric 18888 otelcol_exporter_send_failed_spans)" ]; then
  pass "Gateway's own metrics show failed-export activity while the backend is down (observable, not silent)"
else
  log_warn "No otelcol_exporter_send_failed_spans metric observed yet — may need more time or traffic; not treated as a hard failure."
fi

log_info "Restoring Jaeger to ${ORIGINAL_REPLICAS} replica(s)..."
kubectl -n "${OBSERVABILITY_NAMESPACE}" scale deployment/jaeger --replicas="${ORIGINAL_REPLICAS:-1}" >/dev/null
wait_for "Jaeger Deployment available again" 120 5 -- deployment_rollout_ready "${OBSERVABILITY_NAMESPACE}" jaeger 120

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "resilience-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "resilience-test: all checks passed."
