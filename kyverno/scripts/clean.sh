#!/usr/bin/env bash
# Removes only Kyverno LAB resources — the demo namespace, any temporary
# probe namespaces this lab created, and/or applied policy objects.
# Never touches the Kyverno installation itself (namespace, Helm release,
# CRDs, webhooks) — that is uninstall.sh's job. Never touches any
# namespace or resource this lab didn't create.
#
# Usage: clean.sh [demo|policies|all]   (default: all)
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
  log_section "Removing demo namespace and temporary lab namespaces"
  kubectl delete namespace "${DEMO_NAMESPACE}" --wait=false --ignore-not-found >/dev/null
  log_pass "Deletion requested for namespace ${DEMO_NAMESPACE}."

  TEMP_NAMESPACES="$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^${TEMP_NAMESPACE_PREFIX}" || true)"
  if [ -n "${TEMP_NAMESPACES}" ]; then
    for ns in ${TEMP_NAMESPACES}; do
      kubectl delete namespace "${ns}" --wait=false --ignore-not-found >/dev/null
      log_pass "Deletion requested for temporary namespace ${ns}."
    done
  else
    log_info "No leftover temporary lab namespaces found."
  fi
}

clean_policies() {
  log_section "Removing applied lab policies"
  for dir in audit validate mutate generate cleanup verify-images exceptions advanced production-examples; do
    path="${MODULE_ROOT}/policies/${dir}"
    if [ -d "${path}" ] && [ -n "$(find "${path}" -maxdepth 1 -name '*.yaml' 2>/dev/null)" ]; then
      kubectl delete -f "${path}" --ignore-not-found >/dev/null 2>&1 || true
      log_pass "Removed policies/${dir}/ (if any were applied)."
    fi
  done
}

case "${SCOPE}" in
  demo) clean_demo ;;
  policies) clean_policies ;;
  all) clean_demo; clean_policies ;;
  *) log_fatal "Usage: $0 [demo|policies|all]" ;;
esac

log_pass "clean (${SCOPE}) complete. The Kyverno installation itself (namespace/CRDs/webhooks) is untouched — use 'make uninstall' to remove that."
