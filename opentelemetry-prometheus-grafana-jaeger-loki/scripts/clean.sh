#!/usr/bin/env bash
# Removes only this module's LAB-APPLIED resources (demo app, Collector
# manifests, and/or the observability-namespace workloads) — never the
# Helm releases themselves (that's uninstall-all.sh's job), never
# anything outside this module's 3 namespaces, never Cilium/kube-proxy.
#
# Usage: clean.sh [demo|collector|backends|all]   (default: all)
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
if ! kube_reachable; then
  log_info "No reachable cluster — nothing to clean against a live cluster (local files are untouched by this script regardless)."
  exit 0
fi

SCOPE="${1:-all}"

clean_demo() {
  log_section "Removing demo application from ${OTEL_DEMO_NAMESPACE}"
  kubectl delete namespace "${OTEL_DEMO_NAMESPACE}" --wait=false --ignore-not-found >/dev/null
  log_pass "Deletion requested for ${OTEL_DEMO_NAMESPACE}."

  TEMP_NAMESPACES="$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^${TEMP_NAMESPACE_PREFIX}" || true)"
  for ns in ${TEMP_NAMESPACES}; do
    kubectl delete namespace "${ns}" --wait=false --ignore-not-found >/dev/null
    log_pass "Deletion requested for temporary namespace ${ns}."
  done
}

clean_collector() {
  log_section "Removing Collector agent + gateway manifests (Operator, Prometheus, Jaeger, Loki, Grafana Helm releases untouched)"
  kubectl -n "${OPENTELEMETRY_NAMESPACE}" delete daemonset otel-collector-agent --ignore-not-found >/dev/null
  kubectl -n "${OPENTELEMETRY_NAMESPACE}" delete deployment otel-collector-gateway --ignore-not-found >/dev/null
  kubectl -n "${OPENTELEMETRY_NAMESPACE}" delete configmap otel-collector-agent-config otel-collector-gateway-config --ignore-not-found >/dev/null
  log_pass "Collector manifests removed."
}

clean_backends() {
  log_section "Removing lab-applied Prometheus rule/monitor objects (Helm-managed resources untouched)"
  kubectl delete -f "${MODULE_ROOT}/prometheus/recording-rules/" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f "${MODULE_ROOT}/prometheus/alerts/" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f "${MODULE_ROOT}/prometheus/podmonitors/" --ignore-not-found >/dev/null 2>&1 || true
  log_pass "Lab-applied rule/monitor objects removed."
}

case "${SCOPE}" in
  demo) clean_demo ;;
  collector) clean_collector ;;
  backends) clean_backends ;;
  all) clean_demo; clean_collector; clean_backends ;;
  *) log_fatal "Unknown scope '${SCOPE}'. Valid: demo|collector|backends|all" ;;
esac

log_pass "clean (scope=${SCOPE}) complete."
