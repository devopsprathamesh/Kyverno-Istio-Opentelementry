#!/usr/bin/env bash
# Runtime test: validate-type policies (audit + enforce) reject/report
# as expected against real admission requests. Uses a uniquely-named
# temporary namespace, cleaned up via trap regardless of outcome.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — validate-policy-tests skipped."
  exit 0
fi

NS="${TEMP_NAMESPACE_PREFIX}validate-$(date +%s)"
FAIL=0
cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/validate/require-labels-enforce.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete namespace "${NS}" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_section "validate-policy-tests (namespace: ${NS})"
kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --local -o yaml \
  | kubectl apply -f - >/dev/null

kubectl apply -f "${MODULE_ROOT}/policies/validate/require-labels-enforce.yaml" >/dev/null
wait_for "require-labels-enforce policy Ready" 60 3 -- \
  bash -c "kubectl get clusterpolicy require-labels-enforce -o jsonpath='{.status.ready}' | grep -qx true"

if kubectl run compliant-probe -n "${NS}" --image=registry.k8s.io/pause:3.10 --restart=Never \
     --labels="app.kubernetes.io/name=probe,app.kubernetes.io/part-of=kyverno-learning-lab,owner=platform-team,environment=lab" >/dev/null 2>&1; then
  log_pass "Compliant Pod admitted as expected."
else
  log_fail "Compliant Pod was unexpectedly rejected."
  FAIL=1
fi

if kubectl run noncompliant-probe -n "${NS}" --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null 2>&1; then
  log_fail "Noncompliant Pod was admitted — enforce policy did not block it."
  FAIL=1
else
  log_pass "Noncompliant Pod correctly rejected."
fi

exit "${FAIL}"
