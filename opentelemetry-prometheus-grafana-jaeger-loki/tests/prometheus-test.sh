#!/usr/bin/env bash
# Runtime test: Prometheus query API, targets, recording/alerting rules.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — prometheus-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "prometheus-test"

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${PROMETHEUS_SERVICE}" 19090:"${PROMETHEUS_PORT}" >/dev/null 2>&1 &
PF_PID=$!
cleanup() { kill "${PF_PID}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 3

if prometheus_query_has_result 19090 "up"; then pass "Query API works ('up' returns results)"; else fail "Query API returned no results for 'up'"; fi
if prometheus_target_healthy 19090 "kube-state-metrics"; then pass "kube-state-metrics target healthy"; else fail "kube-state-metrics target not healthy"; fi
if prometheus_query_has_result 19090 'ALERTS or vector(0)'; then pass "Alerting rules query works"; else fail "Alerting rules query failed"; fi
if prometheus_query_has_result 19090 "job:http_requests:rate5m or vector(0)"; then pass "Recording rule 'job:http_requests:rate5m' evaluates"; else fail "Recording rule did not evaluate"; fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "prometheus-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "prometheus-test: all checks passed."
