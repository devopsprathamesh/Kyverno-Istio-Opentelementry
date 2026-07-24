#!/usr/bin/env bash
# Runtime test: Collector Agent/Gateway health and internal metrics.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — collector-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "collector-test"

daemonset_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-agent && pass "Agent DaemonSet Ready on all nodes" || fail "Agent DaemonSet not Ready"
deployment_rollout_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-gateway 5 && pass "Gateway Deployment Ready" || fail "Gateway Deployment not Ready"

kubectl -n "${OPENTELEMETRY_NAMESPACE}" port-forward "svc/${COLLECTOR_GATEWAY_SERVICE}" 13133:"${COLLECTOR_HEALTH_CHECK_PORT}" >/dev/null 2>&1 &
PF_HEALTH=$!
kubectl -n "${OPENTELEMETRY_NAMESPACE}" port-forward "svc/${COLLECTOR_GATEWAY_SERVICE}" 18888:"${COLLECTOR_INTERNAL_METRICS_PORT}" >/dev/null 2>&1 &
PF_METRICS=$!
cleanup() { kill "${PF_HEALTH}" "${PF_METRICS}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 3

if collector_health_check 13133; then pass "Gateway health_check extension OK"; else fail "Gateway health_check extension not OK"; fi
if [ -n "$(collector_internal_metric 18888 otelcol_receiver_accepted)" ]; then pass "Gateway internal metrics endpoint responding"; else fail "Gateway internal metrics endpoint empty"; fi

if ! pod_logs_have_critical_errors "${OPENTELEMETRY_NAMESPACE}" "app=otel-collector-agent"; then
  pass "No panic/fatal-error strings in Agent logs"
else
  fail "Agent logs contain panic/fatal-error strings"
fi
if ! pod_logs_have_critical_errors "${OPENTELEMETRY_NAMESPACE}" "app=otel-collector-gateway"; then
  pass "No panic/fatal-error strings in Gateway logs"
else
  fail "Gateway logs contain panic/fatal-error strings"
fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "collector-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "collector-test: all checks passed."
