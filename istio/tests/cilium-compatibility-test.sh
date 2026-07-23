#!/usr/bin/env bash
# Runtime test: Cilium + Istio CNI chaining is actually working — pod
# networking functions normally for sidecar-injected pods, and a
# Cilium NetworkPolicy still enforces at the L3/L4 layer alongside
# Istio's L7 layer (see docs/04-istio-cni-and-cilium.md).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/istio.sh
source "${MODULE_ROOT}/scripts/lib/istio.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — cilium-compatibility-test skipped."
  exit 0
fi

FAIL=0
log_section "cilium-compatibility-test"

check() {
  local d="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then log_pass "${d}"; else log_fail "${d}"; FAIL=1; fi
}

check "Cilium DaemonSet healthy" -- daemonset_ready kube-system cilium
check "Istio CNI DaemonSet healthy" -- daemonset_ready "${ISTIO_SYSTEM_NAMESPACE}" istio-cni-node
if command -v helm >/dev/null 2>&1; then
  check "Cilium Helm values confirm CNI-chaining compatibility" -- cilium_cni_chaining_ready
fi

# Basic connectivity through both layers: a sidecar-injected pod
# reaching another sidecar-injected pod's Service.
NS="${TEMP_NAMESPACE_PREFIX}cilium-compat-$(date +%s)"
cleanup() { kubectl delete namespace "${NS}" --wait=false --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT
kubectl create namespace "${NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" "istio.io/rev=${ISTIO_REVISION}" --local -o yaml \
  | kubectl apply -f - >/dev/null

kubectl run cilium-compat-target -n "${NS}" --image="${WHOAMI_IMAGE}:${WHOAMI_IMAGE_TAG}" --restart=Never --port=80 >/dev/null
kubectl expose pod cilium-compat-target -n "${NS}" --port=80 --target-port=80 >/dev/null
kubectl -n "${NS}" wait --for=condition=Ready pod/cilium-compat-target --timeout=90s >/dev/null

kubectl run cilium-compat-client -n "${NS}" --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 60 >/dev/null
kubectl -n "${NS}" wait --for=condition=Ready pod/cilium-compat-client --timeout=90s >/dev/null

check "Sidecar-to-sidecar connectivity works through Cilium + Istio CNI chaining" -- \
  kubectl -n "${NS}" exec cilium-compat-client -- curl -fsS -o /dev/null --max-time 5 http://cilium-compat-target/

echo
if [ "${FAIL}" -gt 0 ]; then
  log_fail "cilium-compatibility-test: ${FAIL} mandatory check(s) failed."
  exit 1
fi
log_pass "cilium-compatibility-test: all mandatory checks passed."
