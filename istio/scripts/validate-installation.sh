#!/usr/bin/env bash
# Comprehensive runtime installation validation. Requires Istio already
# installed by scripts/install.sh against a cluster already confirmed
# by scripts/verify-cluster.sh. Prints PASS/WARN/FAIL, exits non-zero
# if any mandatory check fails.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=./lib/istio.sh
source "${MODULE_ROOT}/scripts/lib/istio.sh"

require_cmd kubectl

FAIL_COUNT=0
check() {
  local description="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then log_pass "${description}"; else log_fail "${description}"; FAIL_COUNT=$((FAIL_COUNT + 1)); fi
}
check_warn() {
  local description="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then log_pass "${description}"; else log_warn "${description}"; fi
}

log_section "1/6 — Cluster identity and base networking"
check "Kubernetes API reachable" -- kube_reachable
check "Cilium DaemonSet healthy" -- daemonset_ready kube-system cilium
check_warn "kube-proxy DaemonSet present" -- resource_exists daemonset kube-proxy kube-system
check_warn "CoreDNS healthy" -- deployment_rollout_ready kube-system coredns 5

log_section "2/6 — Istio namespaces, Helm releases, CRDs"
check "Namespace '${ISTIO_SYSTEM_NAMESPACE}' exists" -- namespace_exists "${ISTIO_SYSTEM_NAMESPACE}"
check "Namespace '${ISTIO_INGRESS_NAMESPACE}' exists" -- namespace_exists "${ISTIO_INGRESS_NAMESPACE}"
for release in istio-base istiod istio-cni istio-ingress; do
  ns="${ISTIO_SYSTEM_NAMESPACE}"
  [ "${release}" = "istio-ingress" ] && ns="${ISTIO_INGRESS_NAMESPACE}"
  check "Helm release '${release}' exists" -- helm_release_exists "${release}" "${ns}"
done
for crd in virtualservices.networking.istio.io destinationrules.networking.istio.io \
           gateways.networking.istio.io serviceentries.networking.istio.io \
           sidecars.networking.istio.io peerauthentications.security.istio.io \
           authorizationpolicies.security.istio.io requestauthentications.security.istio.io; do
  check "CRD ${crd} exists" -- crd_exists "${crd}"
done
check "Gateway API CRD (gateways.gateway.networking.k8s.io) exists" -- crd_exists gateways.gateway.networking.k8s.io

log_section "3/6 — Control-plane and data-plane readiness"
check "Istiod deployment available" -- deployment_rollout_ready "${ISTIO_SYSTEM_NAMESPACE}" "istiod-${ISTIO_REVISION}" 5
check "Istio CNI DaemonSet healthy" -- daemonset_ready "${ISTIO_SYSTEM_NAMESPACE}" istio-cni-node
check "Ingress gateway deployment available" -- deployment_rollout_ready "${ISTIO_INGRESS_NAMESPACE}" istio-ingress 5
check "Mutating webhook (sidecar-injector) present" -- any_webhook_exists mutating istio-sidecar-injector
check "Validating webhook (istiod config validation) present" -- any_webhook_exists validating istiod
check_warn "Istiod logs show no obvious critical startup errors" -- \
  bash -c '! pod_logs_have_critical_errors "'"${ISTIO_SYSTEM_NAMESPACE}"'" "app=istiod"'

log_section "4/6 — Services and endpoints"
check "istiod Service has endpoints" -- bash -c "kubectl -n ${ISTIO_SYSTEM_NAMESPACE} get endpoints istiod -o jsonpath='{.subsets}' | grep -q address"
check "istio-ingress Service has endpoints" -- bash -c "kubectl -n ${ISTIO_INGRESS_NAMESPACE} get endpoints istio-ingress -o jsonpath='{.subsets}' | grep -q address"

log_section "5/6 — istioctl analysis"
if istioctl_available; then
  check_warn "'istioctl analyze' reports no errors" -- istioctl analyze --all-namespaces
  check_warn "'istioctl proxy-status' shows at least istiod" -- bash -c "istioctl proxy-status | grep -qi istiod"
else
  log_warn "istioctl not installed — skipped 'istioctl analyze'/'istioctl proxy-status'. See labs/lab-00-prerequisites.md."
fi

log_section "6/6 — Functional probe (temporary, cleaned up automatically)"
PROBE_NS="${TEMP_NAMESPACE_PREFIX}validate-$(date +%s)"
cleanup() { kubectl delete namespace "${PROBE_NS}" --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl create namespace "${PROBE_NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" istio.io/rev="${ISTIO_REVISION}" --local -o yaml \
  | kubectl apply -f - >/dev/null

kubectl run probe-whoami -n "${PROBE_NS}" --image="${WHOAMI_IMAGE}:${WHOAMI_IMAGE_TAG}" --restart=Never \
  --labels="app=probe-whoami" --port="${FRONTEND_PORT}" >/dev/null
if wait_for "probe pod Running with sidecar injected" 90 3 -- \
     bash -c "kubectl get pod probe-whoami -n ${PROBE_NS} -o jsonpath='{.status.containerStatuses[*].name}' | grep -q istio-proxy"; then
  check "Sidecar was injected into the probe pod" -- true
else
  check "Sidecar was injected into the probe pod" -- false
fi

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "validate-installation: ${FAIL_COUNT} mandatory check(s) failed."
  exit 1
fi
log_pass "validate-installation: all mandatory checks passed."
