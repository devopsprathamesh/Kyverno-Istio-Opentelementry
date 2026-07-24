#!/usr/bin/env bash
# Runtime test: end-to-end trace delivery — demo app -> Agent -> Gateway
# -> Jaeger. Requires deploy-demo to have run. Generates a small amount
# of its own traffic if none is found, rather than assuming a specific
# prior state.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — traces-test skipped."
  exit 0
fi
if ! namespace_exists "${OTEL_DEMO_NAMESPACE}"; then
  log_info "Demo namespace not found — run 'make deploy-demo' first. traces-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "traces-test"

kubectl -n "${OTEL_DEMO_NAMESPACE}" run traces-test-client --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 60 >/dev/null 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" wait --for=condition=Ready pod/traces-test-client --timeout=60s >/dev/null 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" exec traces-test-client -- curl -fsS -X POST "http://frontend.${OTEL_DEMO_NAMESPACE}.svc.cluster.local:${DEMO_FRONTEND_PORT}/" >/dev/null 2>&1 || true

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${JAEGER_QUERY_SERVICE}" 16686:"${JAEGER_QUERY_PORT}" >/dev/null 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
  kubectl -n "${OTEL_DEMO_NAMESPACE}" delete pod traces-test-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 5

for svc in frontend order-service inventory-service payment-service; do
  if jaeger_has_traces_for_service 16686 "${svc}"; then
    pass "Traces found for ${svc}"
  else
    fail "No traces found for ${svc} — check Collector Agent/Gateway logs and the Operator's injection status for auto-instrumented services."
  fi
done

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "traces-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "traces-test: all checks passed — full frontend->order-service->{inventory,payment}-service chain traced."
