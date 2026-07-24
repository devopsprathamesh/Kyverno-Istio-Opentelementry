#!/usr/bin/env bash
# Runtime test: Jaeger Query UI + direct OTLP ingestion (bypassing the
# Collector — isolates Jaeger itself from the pipeline in front of it).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — jaeger-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "jaeger-test"

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${JAEGER_QUERY_SERVICE}" 16686:"${JAEGER_QUERY_PORT}" >/dev/null 2>&1 &
PF_QUERY=$!
kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${JAEGER_COLLECTOR_OTLP_GRPC_SERVICE}" 14318:"${JAEGER_OTLP_HTTP_PORT}" >/dev/null 2>&1 &
PF_OTLP=$!
cleanup() { kill "${PF_QUERY}" "${PF_OTLP}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 3

if curl -fsS -o /dev/null "http://127.0.0.1:16686/" 2>/dev/null; then pass "Query UI reachable"; else fail "Query UI not reachable"; fi

TRACE_ID="$(send_test_otlp_trace 14318 jaeger-test-probe 2>/dev/null || true)"
if [ -n "${TRACE_ID}" ]; then
  pass "Test OTLP trace accepted (trace_id=${TRACE_ID})"
  sleep 3
  if jaeger_has_traces_for_service 16686 jaeger-test-probe; then
    pass "Test trace is searchable in Jaeger"
  else
    fail "Test trace was accepted but is not searchable"
  fi
else
  fail "Could not send test OTLP trace to Jaeger's collector"
fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "jaeger-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "jaeger-test: all checks passed."
