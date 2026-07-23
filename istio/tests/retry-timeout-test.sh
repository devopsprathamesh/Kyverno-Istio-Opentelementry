#!/usr/bin/env bash
# Runtime test: a VirtualService timeout actually bounds request
# duration. Uses the fault-delay VirtualService (3s delay) against a
# tighter-than-3s timeout to force a timeout deterministically, rather
# than depending on real network flakiness.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — retry-timeout-test skipped."
  exit 0
fi

log_section "retry-timeout-test"

cleanup() {
  kubectl delete -f "${MODULE_ROOT}/demo/resilience/virtualservice-fault-delay.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${DEMO_NAMESPACE}" delete pod retry-timeout-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 3s fixed delay on inventory-service, then a 1s VirtualService timeout
# on the SAME host wins over the delay (a shorter, ad-hoc override for
# this specific test rather than reusing the lab's 5s default, so the
# test completes quickly and deterministically).
kubectl apply -f "${MODULE_ROOT}/demo/resilience/virtualservice-fault-delay.yaml" >/dev/null
kubectl patch virtualservice inventory-service-fault-delay -n "${DEMO_NAMESPACE}" --type merge \
  -p '{"spec":{"http":[{"fault":{"delay":{"percentage":{"value":100.0},"fixedDelay":"3s"}},"timeout":"1s","route":[{"destination":{"host":"inventory-service"}}]}]}}' >/dev/null

kubectl run retry-timeout-client -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 60 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready pod/retry-timeout-client --timeout=60s >/dev/null

START="$(date +%s)"
HTTP_CODE="$(kubectl -n "${DEMO_NAMESPACE}" exec retry-timeout-client -- curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://inventory-service/ 2>/dev/null || echo "000")"
ELAPSED=$(( $(date +%s) - START ))

log_info "Response code: ${HTTP_CODE}, elapsed: ${ELAPSED}s (100% 3s delay vs. 1s VirtualService timeout)"
if [ "${HTTP_CODE}" = "504" ] && [ "${ELAPSED}" -lt 3 ]; then
  log_pass "VirtualService timeout correctly cut off the delayed request before the full 3s delay (504 in ${ELAPSED}s)."
  exit 0
else
  log_fail "Expected a 504 in under 3s (timeout enforced); got ${HTTP_CODE} in ${ELAPSED}s."
  exit 1
fi
