#!/usr/bin/env bash
# Runtime test: abort fault injection actually returns the configured
# HTTP status for the configured percentage of requests (checked
# approximately, same statistical-tolerance approach as
# traffic-routing-test.sh).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — fault-injection-test skipped."
  exit 0
fi

log_section "fault-injection-test (abort fault, 30% -> HTTP 503)"

cleanup() {
  kubectl delete -f "${MODULE_ROOT}/demo/resilience/virtualservice-fault-abort.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${DEMO_NAMESPACE}" delete pod fault-injection-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply -f "${MODULE_ROOT}/demo/resilience/virtualservice-fault-abort.yaml" >/dev/null
sleep 3

kubectl run fault-injection-client -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 60 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready pod/fault-injection-client --timeout=60s >/dev/null

TOTAL=50
ABORT_COUNT=0
for ((i = 1; i <= TOTAL; i++)); do
  CODE="$(kubectl -n "${DEMO_NAMESPACE}" exec fault-injection-client -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://payment-service/ 2>/dev/null || echo 000)"
  [ "${CODE}" = "503" ] && ABORT_COUNT=$((ABORT_COUNT + 1))
done

ABORT_PERCENT=$((ABORT_COUNT * 100 / TOTAL))
log_info "Observed abort rate: ${ABORT_COUNT}/${TOTAL} (${ABORT_PERCENT}%, target ~30%)"

LOWER=$((30 - TRAFFIC_STATISTICAL_TOLERANCE_PERCENT))
UPPER=$((30 + TRAFFIC_STATISTICAL_TOLERANCE_PERCENT))
if [ "${ABORT_PERCENT}" -ge "${LOWER}" ] && [ "${ABORT_PERCENT}" -le "${UPPER}" ]; then
  log_pass "Abort fault rate within statistical tolerance."
  exit 0
else
  log_fail "Abort fault rate outside statistical tolerance (expected ${LOWER}-${UPPER}%, got ${ABORT_PERCENT}%)."
  exit 1
fi
