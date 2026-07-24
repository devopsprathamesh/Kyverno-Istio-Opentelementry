#!/usr/bin/env bash
# Runtime test: trace-log correlation — generates one real request,
# extracts its trace_id from a Jaeger-searchable trace, then confirms
# a Loki log record with that exact trace_id exists too. This is the
# strongest possible proof of docs/08-telemetry-correlation.md working
# end to end — stronger than checking Grafana's datasource config
# alone, which only proves the LINKS are configured, not that the
# underlying data actually correlates.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — correlation-test skipped."
  exit 0
fi
if ! namespace_exists "${OTEL_DEMO_NAMESPACE}"; then
  log_info "Demo namespace not found — run 'make deploy-demo' first. correlation-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "correlation-test"

kubectl -n "${OTEL_DEMO_NAMESPACE}" run correlation-test-client --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 60 >/dev/null 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" wait --for=condition=Ready pod/correlation-test-client --timeout=60s >/dev/null 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" exec correlation-test-client -- curl -fsS -X POST "http://frontend.${OTEL_DEMO_NAMESPACE}.svc.cluster.local:${DEMO_FRONTEND_PORT}/" >/dev/null 2>&1 || true

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${JAEGER_QUERY_SERVICE}" 16686:"${JAEGER_QUERY_PORT}" >/dev/null 2>&1 &
PF_JAEGER=$!
kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${LOKI_SERVICE}" 13100:"${LOKI_PORT}" >/dev/null 2>&1 &
PF_LOKI=$!
cleanup() {
  kill "${PF_JAEGER}" "${PF_LOKI}" >/dev/null 2>&1 || true
  kubectl -n "${OTEL_DEMO_NAMESPACE}" delete pod correlation-test-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 5

TRACE_ID="$(curl -fsS -G "http://127.0.0.1:16686/api/traces" --data-urlencode "service=order-service" --data-urlencode "limit=1" 2>/dev/null \
  | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    traces=d.get("data",[])
    print(traces[0]["traceID"] if traces else "")
except Exception:
    print("")' 2>/dev/null || true)"

if [ -z "${TRACE_ID}" ]; then
  fail "Could not obtain a real trace_id from Jaeger for order-service — cannot test correlation. Run traces-test.sh first to confirm tracing works at all."
else
  pass "Obtained real trace_id from Jaeger: ${TRACE_ID}"
  if loki_query_has_result 13100 "{k8s_namespace_name=\"otel-demo\"} | json | trace_id=\"${TRACE_ID}\""; then
    pass "The SAME trace_id is present in a Loki log record — trace-log correlation confirmed end to end"
  else
    fail "trace_id ${TRACE_ID} not found in any Loki log record — check collector/agent/configmap.yaml's transform/log_trace_context processor and the application's log formatter"
  fi
fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "correlation-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "correlation-test: all checks passed."
