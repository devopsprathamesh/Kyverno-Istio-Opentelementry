#!/usr/bin/env bash
# Removes only Istio LAB resources — the demo/external namespaces, any
# temporary probe namespaces this lab created, and/or applied
# traffic/security/resilience/egress/policy configuration objects.
# Never touches the Istio installation itself (istio-system/istio-
# ingress, Helm releases, CRDs) — that is uninstall.sh's job. Never
# touches any namespace or resource this lab didn't create, and never
# silently removes a user-created Istio configuration object it doesn't
# recognize as its own (everything this lab applies carries the
# LAB_RESOURCE_LABEL_KEY=LAB_RESOURCE_LABEL_VALUE label).
#
# Usage: clean.sh [demo|config|all]   (default: all)
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
if ! kube_reachable; then
  log_info "No reachable cluster — nothing to clean against a live cluster (local files are untouched by this script regardless)."
  exit 0
fi

SCOPE="${1:-all}"

clean_demo() {
  log_section "Removing demo/external namespaces and temporary lab namespaces"
  kubectl delete namespace "${DEMO_NAMESPACE}" "${EXTERNAL_NAMESPACE}" --wait=false --ignore-not-found >/dev/null
  log_pass "Deletion requested for ${DEMO_NAMESPACE} and ${EXTERNAL_NAMESPACE}."

  TEMP_NAMESPACES="$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^${TEMP_NAMESPACE_PREFIX}" || true)"
  for ns in ${TEMP_NAMESPACES}; do
    kubectl delete namespace "${ns}" --wait=false --ignore-not-found >/dev/null
    log_pass "Deletion requested for temporary namespace ${ns}."
  done
}

clean_config() {
  log_section "Removing lab-applied Istio config objects (labeled ${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE})"
  for kind in virtualservices destinationrules gateways serviceentries sidecars \
              peerauthentications authorizationpolicies requestauthentications; do
    kubectl delete "${kind}" -A -l "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --ignore-not-found >/dev/null 2>&1 || true
  done
  log_pass "Lab-labeled config objects removed. User-created Istio configuration without this label was left untouched."
}

case "${SCOPE}" in
  demo) clean_demo ;;
  config) clean_config ;;
  all) clean_demo; clean_config ;;
  *) log_fatal "Usage: $0 [demo|config|all]" ;;
esac

log_pass "clean (${SCOPE}) complete. The Istio installation itself (istio-system/istio-ingress/CRDs) is untouched — use 'make uninstall' to remove that."
