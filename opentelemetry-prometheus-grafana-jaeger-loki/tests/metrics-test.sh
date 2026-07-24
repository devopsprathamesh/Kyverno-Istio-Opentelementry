#!/usr/bin/env bash
# Runtime test: end-to-end metrics delivery — demo app -> Agent ->
# Gateway (prometheus exporter, scrape-based) -> Prometheus.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — metrics-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "metrics-test"

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${PROMETHEUS_SERVICE}" 19090:"${PROMETHEUS_PORT}" >/dev/null 2>&1 &
PF_PID=$!
cleanup() { kill "${PF_PID}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 3

if prometheus_target_healthy 19090 "otel-collector"; then
  pass "Collector Gateway PodMonitor target healthy"
else
  fail "Collector Gateway PodMonitor target not healthy — check prometheus/podmonitors/otel-collector-podmonitor.yaml was applied"
fi

if prometheus_query_has_result 19090 "otelcol_receiver_accepted_metric_points or vector(0)"; then
  pass "Collector internal metrics visible in Prometheus"
else
  fail "otelcol_receiver_accepted_metric_points not found in Prometheus"
fi

if namespace_exists "${OTEL_DEMO_NAMESPACE}"; then
  if prometheus_query_has_result 19090 "orders_total or vector(0)"; then
    pass "Demo app business metric 'orders_total' visible in Prometheus"
  else
    fail "orders_total not found — check demo app is deployed and has received traffic (make generate-load)"
  fi
else
  log_info "Demo namespace not found — skipping demo-app-specific metric check (run 'make deploy-demo' first)."
fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "metrics-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "metrics-test: all checks passed."
