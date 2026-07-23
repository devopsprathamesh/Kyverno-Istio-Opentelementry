#!/usr/bin/env bash
# Runtime test: generate policy creates the expected resource when its
# trigger condition (a namespace label) is met, and synchronize keeps it
# in place.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — generate-policy-tests skipped."
  exit 0
fi

NS="${TEMP_NAMESPACE_PREFIX}generate-$(date +%s)"
FAIL=0
cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/generate/default-network-policy.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete namespace "${NS}" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_section "generate-policy-tests (namespace: ${NS})"
kubectl apply -f "${MODULE_ROOT}/policies/generate/default-network-policy.yaml" >/dev/null

kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" generate-default-networkpolicy=enabled --local -o yaml \
  | kubectl apply -f - >/dev/null

if wait_for "Generated NetworkPolicy present in ${NS}" 60 3 -- \
     bash -c "kubectl get networkpolicy default-namespace-policy -n ${NS} >/dev/null 2>&1"; then
  log_pass "Generate policy created the expected NetworkPolicy."
else
  log_fail "Generated NetworkPolicy never appeared."
  FAIL=1
fi

# Synchronization check: delete the generated resource, confirm Kyverno recreates it.
kubectl delete networkpolicy default-namespace-policy -n "${NS}" >/dev/null 2>&1 || true
if wait_for "NetworkPolicy re-synchronized after manual deletion" 60 3 -- \
     bash -c "kubectl get networkpolicy default-namespace-policy -n ${NS} >/dev/null 2>&1"; then
  log_pass "synchronize: true correctly recreated the deleted NetworkPolicy."
else
  log_fail "NetworkPolicy was not recreated after manual deletion — synchronize may not be working as expected."
  FAIL=1
fi

# Negative case: a namespace WITHOUT the trigger label should get nothing.
NS2="${TEMP_NAMESPACE_PREFIX}generate-neg-$(date +%s)"
kubectl create namespace "${NS2}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --local -o yaml \
  | kubectl apply -f - >/dev/null
sleep 5
if kubectl get networkpolicy default-namespace-policy -n "${NS2}" >/dev/null 2>&1; then
  log_fail "NetworkPolicy was generated in a namespace WITHOUT the trigger label — selector match is too broad."
  FAIL=1
else
  log_pass "Namespace without the trigger label correctly got no generated NetworkPolicy."
fi
kubectl delete namespace "${NS2}" --wait=false --ignore-not-found >/dev/null 2>&1 || true

exit "${FAIL}"
