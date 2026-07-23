#!/usr/bin/env bash
# Runtime test: mutate policy actually patches a resource, and never
# overwrites an already-set value.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — mutate-policy-tests skipped."
  exit 0
fi

NS="${TEMP_NAMESPACE_PREFIX}mutate-$(date +%s)"
FAIL=0
cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/mutate/add-default-labels.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete namespace "${NS}" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_section "mutate-policy-tests (namespace: ${NS})"
kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --local -o yaml \
  | kubectl apply -f - >/dev/null

kubectl apply -f "${MODULE_ROOT}/policies/mutate/add-default-labels.yaml" >/dev/null

# Case 1: label missing -> should be added.
kubectl run mutate-missing -n "${NS}" --image=registry.k8s.io/pause:3.10 --restart=Never \
  --labels="app.kubernetes.io/name=mutate-missing" >/dev/null
ENV_VALUE="$(kubectl get pod mutate-missing -n "${NS}" -o jsonpath='{.metadata.labels.environment}')"
if [ "${ENV_VALUE}" = "lab" ]; then
  log_pass "Missing 'environment' label was added (value: ${ENV_VALUE})."
else
  log_fail "Missing 'environment' label was NOT added as expected."
  FAIL=1
fi

# Case 2: label already set to a non-default value -> must NOT be overwritten.
kubectl run mutate-preset -n "${NS}" --image=registry.k8s.io/pause:3.10 --restart=Never \
  --labels="app.kubernetes.io/name=mutate-preset,environment=production" >/dev/null
ENV_VALUE_PRESET="$(kubectl get pod mutate-preset -n "${NS}" -o jsonpath='{.metadata.labels.environment}')"
if [ "${ENV_VALUE_PRESET}" = "production" ]; then
  log_pass "Pre-set 'environment=production' label was left untouched (addIfNotPresent worked)."
else
  log_fail "Pre-set 'environment' label was overwritten (got: ${ENV_VALUE_PRESET}) — mutation should never overwrite an intentional value."
  FAIL=1
fi

exit "${FAIL}"
