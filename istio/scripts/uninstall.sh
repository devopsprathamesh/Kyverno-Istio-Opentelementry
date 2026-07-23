#!/usr/bin/env bash
# Removes the Istio Helm releases (reverse install order) and
# istio-system/istio-ingress namespaces. CRD removal requires explicit
# REMOVE_CRDS=true (deletes Istio CRDs — every VirtualService/
# DestinationRule/etc. cluster-wide, not just this lab's own). Gateway
# API CRDs are only ever removed if THIS lab installed them (tracked via
# .generated/gateway-api-crds-owned.marker written by install.sh) —
# never removed if they pre-existed, since another consumer might
# depend on them.
#
# Never touches Cilium, kube-proxy, or the cluster itself.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm
if ! kube_reachable; then
  log_fatal "No reachable cluster. Nothing to uninstall against."
fi

log_section "Uninstalling Istio"
log_info "DESTRUCTIVE: this removes the istio-ingress, istio-cni, istiod, and istio-base Helm releases and their namespaces."

if helm_release_exists istio-ingress "${ISTIO_INGRESS_NAMESPACE}"; then
  helm uninstall istio-ingress --namespace "${ISTIO_INGRESS_NAMESPACE}"
  log_pass "Helm release 'istio-ingress' removed."
fi
for release in istio-cni istiod istio-base; do
  if helm_release_exists "${release}" "${ISTIO_SYSTEM_NAMESPACE}"; then
    helm uninstall "${release}" --namespace "${ISTIO_SYSTEM_NAMESPACE}"
    log_pass "Helm release '${release}' removed."
  fi
done

kubectl delete namespace "${ISTIO_INGRESS_NAMESPACE}" "${ISTIO_SYSTEM_NAMESPACE}" --wait=false --ignore-not-found >/dev/null
log_pass "Deletion requested for ${ISTIO_INGRESS_NAMESPACE} and ${ISTIO_SYSTEM_NAMESPACE}."

if [ "${REMOVE_CRDS:-false}" = "true" ]; then
  log_info "REMOVE_CRDS=true — deleting Istio CRDs. WARNING: this deletes every VirtualService, DestinationRule, Gateway, ServiceEntry, Sidecar, PeerAuthentication, AuthorizationPolicy, and RequestAuthentication cluster-wide, not just this lab's own."
  ISTIO_CRDS="$(kubectl get crd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -E 'istio\.io$' || true)"
  for crd in ${ISTIO_CRDS}; do
    kubectl delete crd "${crd}" --ignore-not-found >/dev/null
    log_pass "Deleted CRD ${crd}"
  done

  if [ -f "${GENERATED_DIR}/gateway-api-crds-owned.marker" ]; then
    log_info "This lab installed the Gateway API CRDs (ownership marker found) — removing them too."
    kubectl delete -f "${GATEWAY_API_CRDS_URL}" --ignore-not-found >/dev/null 2>&1 || true
    rm -f "${GENERATED_DIR}/gateway-api-crds-owned.marker"
  else
    log_info "No Gateway API CRD ownership marker found — leaving Gateway API CRDs in place (they either pre-existed, or their origin is unknown; never delete shared CRDs this lab didn't confirm installing)."
  fi
else
  log_info "CRDs left in place (default). Set REMOVE_CRDS=true to also delete them — see the warning above before doing so."
fi

log_pass "Uninstall complete. Cilium, kube-proxy, and the cluster itself were never touched."
