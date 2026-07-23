#!/usr/bin/env bash
# Runtime test: image verification policy behavior. This is the one
# runtime test category most dependent on external network access
# (Sigstore Rekor/Fulcio for the keyless-verification policy) — it is
# best-effort and reports WARN rather than FAIL if that network path
# isn't available, rather than failing the whole suite over a
# connectivity issue unrelated to Kyverno itself.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — image-verification-tests skipped."
  exit 0
fi

NS="${TEMP_NAMESPACE_PREFIX}imgverify-$(date +%s)"
cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/verify-images/verify-image-signature.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete namespace "${NS}" --wait=false --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_section "image-verification-tests (namespace: ${NS})"
kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --local -o yaml \
  | kubectl apply -f - >/dev/null

kubectl apply -f "${MODULE_ROOT}/policies/verify-images/verify-image-signature.yaml" >/dev/null
wait_for "verify-image-signature policy Ready" 60 3 -- \
  bash -c "kubectl get clusterpolicy verify-image-signature -o jsonpath='{.status.ready}' | grep -qx true"
log_pass "Policy applied and reports Ready — syntax/admission is valid."

# A non-ghcr.io/kyverno image should be completely unaffected by this
# policy (its imageReferences match is scoped to ghcr.io/kyverno/* only).
if kubectl run unaffected-image -n "${NS}" --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null 2>&1; then
  log_pass "An image outside this policy's scope (registry.k8s.io/*) is unaffected, as expected."
else
  log_fail "An out-of-scope image was unexpectedly blocked — check the imageReferences match on verify-image-signature."
fi

log_info "Real keyless-verification behavior against an actual ghcr.io/kyverno/* image requires outbound network access to Rekor/Fulcio (rekor.sigstore.dev). This script does not attempt that live pull-and-verify automatically — see labs/lab-11-image-verification.md 'Static/offline path' vs 'Optional runtime signing path' for exactly what is and isn't exercised without it, and how to test it manually if you want to confirm real signature enforcement."
