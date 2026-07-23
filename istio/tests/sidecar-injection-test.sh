#!/usr/bin/env bash
# Runtime test: automatic sidecar injection actually happens for pods
# in a labeled namespace, and does NOT happen for pods in an unlabeled
# one.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — sidecar-injection-test skipped."
  exit 0
fi

FAIL=0
NS="${TEMP_NAMESPACE_PREFIX}injection-$(date +%s)"
cleanup() { kubectl delete namespace "${NS}" --wait=false --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

log_section "sidecar-injection-test"

kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" "istio.io/rev=${ISTIO_REVISION}" --local -o yaml \
  | kubectl apply -f - >/dev/null

kubectl run injected-pod -n "${NS}" --image="${WHOAMI_IMAGE}:${WHOAMI_IMAGE_TAG}" --restart=Never >/dev/null
if wait_for "injected-pod has istio-proxy container" 60 3 -- \
     bash -c "kubectl get pod injected-pod -n ${NS} -o jsonpath='{.spec.containers[*].name}' | grep -q istio-proxy"; then
  log_pass "Sidecar injected as expected in labeled namespace."
else
  log_fail "Sidecar was NOT injected in a namespace labeled for injection."
  FAIL=1
fi

NS_NOINJECT="${TEMP_NAMESPACE_PREFIX}noinjection-$(date +%s)"
kubectl create namespace "${NS_NOINJECT}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --local -o yaml \
  | kubectl apply -f - >/dev/null
kubectl run uninjected-pod -n "${NS_NOINJECT}" --image="${WHOAMI_IMAGE}:${WHOAMI_IMAGE_TAG}" --restart=Never >/dev/null
kubectl wait --for=condition=Ready "pod/uninjected-pod" -n "${NS_NOINJECT}" --timeout=60s >/dev/null
CONTAINER_COUNT="$(kubectl get pod uninjected-pod -n "${NS_NOINJECT}" -o jsonpath='{.spec.containers[*].name}' | wc -w)"
if [ "${CONTAINER_COUNT}" -eq 1 ]; then
  log_pass "No sidecar injected in an unlabeled namespace, as expected (1 container)."
else
  log_fail "Unexpected container count (${CONTAINER_COUNT}) in unlabeled namespace pod."
  FAIL=1
fi
kubectl delete namespace "${NS_NOINJECT}" --wait=false >/dev/null 2>&1 || true

exit "${FAIL}"
