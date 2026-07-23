#!/usr/bin/env bash
# Runtime test: canary traffic-shifting (90/10) produces a response
# distribution within TRAFFIC_STATISTICAL_TOLERANCE_PERCENT of the
# configured weights — not an exact match, since this is a statistical,
# not deterministic, distribution.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — traffic-routing-test skipped."
  exit 0
fi

log_section "traffic-routing-test (90/10 canary, statistical tolerance ${TRAFFIC_STATISTICAL_TOLERANCE_PERCENT}%)"

cleanup() {
  kubectl delete -f "${MODULE_ROOT}/demo/traffic/virtualservice-canary-90-10.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f "${MODULE_ROOT}/demo/traffic/destinationrule-frontend.yaml" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply -f "${MODULE_ROOT}/demo/traffic/destinationrule-frontend.yaml" >/dev/null
kubectl apply -f "${MODULE_ROOT}/demo/traffic/virtualservice-canary-90-10.yaml" >/dev/null
sleep 3

CLIENT_POD="traffic-routing-test-$(date +%s)"
kubectl run "${CLIENT_POD}" -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 120 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready "pod/${CLIENT_POD}" --timeout=60s >/dev/null

V1_COUNT=0
V2_COUNT=0
TOTAL=100
for ((i = 1; i <= TOTAL; i++)); do
  BODY="$(kubectl -n "${DEMO_NAMESPACE}" exec "${CLIENT_POD}" -- curl -s --max-time 5 http://frontend/ 2>/dev/null || true)"
  if grep -q "frontend-v2" <<<"${BODY}"; then
    V2_COUNT=$((V2_COUNT + 1))
  elif grep -q "frontend-v1" <<<"${BODY}"; then
    V1_COUNT=$((V1_COUNT + 1))
  fi
done
kubectl -n "${DEMO_NAMESPACE}" delete pod "${CLIENT_POD}" --ignore-not-found >/dev/null 2>&1 || true

V2_PERCENT=$((V2_COUNT * 100 / TOTAL))
log_info "Observed distribution: v1=${V1_COUNT} v2=${V2_COUNT} (v2 = ${V2_PERCENT}%, target 10% +/- ${TRAFFIC_STATISTICAL_TOLERANCE_PERCENT}%)"

LOWER=$((10 - TRAFFIC_STATISTICAL_TOLERANCE_PERCENT))
UPPER=$((10 + TRAFFIC_STATISTICAL_TOLERANCE_PERCENT))
if [ "${V2_PERCENT}" -ge "${LOWER}" ] && [ "${V2_PERCENT}" -le "${UPPER}" ]; then
  log_pass "Canary distribution within statistical tolerance."
  exit 0
else
  log_fail "Canary distribution outside statistical tolerance (expected ${LOWER}-${UPPER}%, got ${V2_PERCENT}%)."
  exit 1
fi
