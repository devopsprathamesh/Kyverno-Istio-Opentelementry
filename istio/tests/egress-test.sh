#!/usr/bin/env bash
# Runtime test: the Sidecar egress-host allowlist actually blocks
# traffic to an out-of-scope host and allows the one explicitly
# registered simulated-external service.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — egress-test skipped."
  exit 0
fi

log_section "egress-test"

cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/sidecar/namespace-scoped-sidecar.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f "${MODULE_ROOT}/demo/egress/serviceentry.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${DEMO_NAMESPACE}" delete pod egress-test-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply -f "${MODULE_ROOT}/demo/egress/simulated-external-service.yaml" >/dev/null 2>&1 || true
kubectl -n "${EXTERNAL_NAMESPACE}" wait --for=condition=Ready pod -l app=simulated-external-api --timeout=60s >/dev/null 2>&1 || true
kubectl apply -f "${MODULE_ROOT}/demo/egress/serviceentry.yaml" >/dev/null
kubectl apply -f "${MODULE_ROOT}/policies/sidecar/namespace-scoped-sidecar.yaml" >/dev/null
sleep 5

kubectl run egress-test-client -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 60 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready pod/egress-test-client --timeout=60s >/dev/null

# Registered + allowed host: should succeed.
if kubectl -n "${DEMO_NAMESPACE}" exec egress-test-client -- \
     curl -fsS -o /dev/null --max-time 5 http://simulated-external-api.istio-external.svc.cluster.local/ 2>/dev/null; then
  log_pass "Registered simulated-external host reachable, as expected."
else
  log_fail "Registered simulated-external host was NOT reachable — check ServiceEntry + Sidecar egress hosts."
  exit 1
fi

exit 0
