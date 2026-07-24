#!/usr/bin/env bash
# Runtime test: Loki readiness + direct OTLP log ingestion (bypassing
# the Collector — isolates Loki itself from the pipeline in front of it).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — loki-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "loki-test"

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${LOKI_SERVICE}" 13100:"${LOKI_PORT}" >/dev/null 2>&1 &
PF_PID=$!
cleanup() { kill "${PF_PID}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 3

if curl -fsS -o /dev/null "http://127.0.0.1:13100/ready" 2>/dev/null; then pass "Readiness endpoint OK"; else fail "Readiness endpoint not OK"; fi

send_test_otlp_log 13100 loki-test-probe "loki-test-probe test log line" >/dev/null 2>&1
sleep 3
if loki_query_has_result 13100 '{service_name="loki-test-probe"}'; then
  pass "Test OTLP log is searchable in Loki"
else
  fail "Test OTLP log was not found (ingestion or the service_name label mapping may be broken — see docs/06-logs.md)"
fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "loki-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "loki-test: all checks passed."
