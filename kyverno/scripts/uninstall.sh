#!/usr/bin/env bash
# Removes the Kyverno Helm release and namespace, and — only if
# REMOVE_CRDS=true is explicitly set — the Kyverno CRDs themselves.
#
# CRD deletion is NOT the default because deleting a CRD deletes every
# custom resource of that type cluster-wide (every ClusterPolicy, Policy,
# PolicyException, PolicyReport, etc. — including anything a learner
# created outside this lab's own policies/ directory). This script warns
# loudly and requires the explicit opt-in rather than silently doing it.
#
# Never touches Cilium, Hubble, kube-proxy, or the cluster itself.
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

log_section "Uninstalling Kyverno"
log_info "DESTRUCTIVE: this removes the 'kyverno' Helm release and namespace '${KYVERNO_NAMESPACE}'."

if helm_release_exists kyverno "${KYVERNO_NAMESPACE}"; then
  helm uninstall kyverno --namespace "${KYVERNO_NAMESPACE}"
  log_pass "Helm release 'kyverno' removed."
else
  log_info "No 'kyverno' Helm release found — nothing to uninstall there."
fi

kubectl delete namespace "${KYVERNO_NAMESPACE}" --wait=false --ignore-not-found >/dev/null
log_pass "Deletion requested for namespace '${KYVERNO_NAMESPACE}'."

if [ "${REMOVE_CRDS:-false}" = "true" ]; then
  log_info "REMOVE_CRDS=true — deleting Kyverno CRDs. WARNING: this deletes every ClusterPolicy, Policy, PolicyException, PolicyReport, CleanupPolicy, and every other Kyverno custom resource cluster-wide, not just this lab's own."
  KYVERNO_CRDS="$(kubectl get crd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep 'kyverno.io$' || true)"
  if [ -n "${KYVERNO_CRDS}" ]; then
    for crd in ${KYVERNO_CRDS}; do
      kubectl delete crd "${crd}" --ignore-not-found >/dev/null
      log_pass "Deleted CRD ${crd}"
    done
  else
    log_info "No Kyverno CRDs found."
  fi
else
  log_info "CRDs left in place (default). Set REMOVE_CRDS=true to also delete them — see the warning above before doing so."
fi

log_pass "Uninstall complete. Cilium, Hubble, kube-proxy, and the cluster itself were never touched."
