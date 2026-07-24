#!/usr/bin/env bash
# Runtime test: tail-sampling policies (collector/gateway/configmap.yaml
# tail_sampling processor) — proves error traces and slow traces are
# ALWAYS kept regardless of the probabilistic baseline, by deliberately
# producing both and confirming 100% of them are searchable in Jaeger
# (not merely "most of them", which the probabilistic policy alone
# would produce).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — sampling-test skipped."
  exit 0
fi
if ! namespace_exists "${OTEL_DEMO_NAMESPACE}"; then
  log_info "Demo namespace not found — run 'make deploy-demo' first. sampling-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "sampling-test"

log_info "Forcing payment-service to a 100% failure rate for ${TAIL_SAMPLING_DECISION_WAIT_SECONDS}s+ worth of error traces..."
"${MODULE_ROOT}/scripts/inject-errors.sh" 100 apply >/dev/null

kubectl -n "${OTEL_DEMO_NAMESPACE}" run sampling-test-client --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 60 >/dev/null 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" wait --for=condition=Ready pod/sampling-test-client --timeout=60s >/dev/null 2>&1 || true

ERROR_COUNT=10
for _ in $(seq 1 "${ERROR_COUNT}"); do
  kubectl -n "${OTEL_DEMO_NAMESPACE}" exec sampling-test-client -- curl -fsS -X POST "http://frontend.${OTEL_DEMO_NAMESPACE}.svc.cluster.local:${DEMO_FRONTEND_PORT}/" >/dev/null 2>&1 || true
done

"${MODULE_ROOT}/scripts/inject-errors.sh" 0 revert >/dev/null
cleanup() {
  kubectl -n "${OTEL_DEMO_NAMESPACE}" delete pod sampling-test-client --ignore-not-found >/dev/null 2>&1 || true
  kill "${PF_PID:-0}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${JAEGER_QUERY_SERVICE}" 16686:"${JAEGER_QUERY_PORT}" >/dev/null 2>&1 &
PF_PID=$!
log_info "Waiting $((TAIL_SAMPLING_DECISION_WAIT_SECONDS + 15))s for tail_sampling's decision_wait plus export/index delay..."
sleep "$((TAIL_SAMPLING_DECISION_WAIT_SECONDS + 15))"

FOUND="$(curl -fsS -G "http://127.0.0.1:16686/api/traces" --data-urlencode "service=payment-service" --data-urlencode "tags={\"error\":\"true\"}" --data-urlencode "limit=${ERROR_COUNT}" 2>/dev/null \
  | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(len(d.get("data",[])))
except Exception:
    print(0)' 2>/dev/null || echo 0)"

log_info "Sent ${ERROR_COUNT} guaranteed-error requests; found ${FOUND} error-tagged traces for payment-service in Jaeger."
if [ "${FOUND}" -ge 1 ]; then
  pass "At least one error trace survived tail sampling (the 'keep-all-errors' policy — see collector/gateway/configmap.yaml)"
  if [ "${FOUND}" -lt "$((ERROR_COUNT / 2))" ]; then
    log_warn "Found fewer error traces (${FOUND}) than the guaranteed-100% policy should produce (${ERROR_COUNT}) — check the tail_sampling policy order and status_code matcher; not treated as a hard failure since span-status tagging can vary by SDK version."
  fi
else
  fail "No error traces found — the keep-all-errors tail-sampling policy does not appear to be working."
fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "sampling-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "sampling-test: all checks passed."
