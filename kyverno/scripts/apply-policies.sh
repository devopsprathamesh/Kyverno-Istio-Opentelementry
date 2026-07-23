#!/usr/bin/env bash
# Applies policies from one policy-type directory (or all of them) under
# policies/. Usage: apply-policies.sh <audit|validate|mutate|generate|
# cleanup|verify-images|exceptions|advanced|production-examples|all>
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
TYPE="${1:-}"
VALID_TYPES="audit validate mutate generate cleanup verify-images exceptions advanced production-examples"

if [ -z "${TYPE}" ]; then
  log_fatal "Usage: $0 <${VALID_TYPES// /|}|all>"
fi
if ! kube_reachable; then
  log_fatal "No reachable cluster. Run 'make verify-cluster' first."
fi

apply_dir() {
  local dir="$1" path="${MODULE_ROOT}/policies/$1"
  if [ -d "${path}" ] && [ -n "$(find "${path}" -maxdepth 1 -name '*.yaml' 2>/dev/null)" ]; then
    kubectl apply -f "${path}"
    log_pass "Applied policies/${dir}/"
  else
    log_info "policies/${dir}/ has no policy YAMLs yet, skipping."
  fi
}

if [ "${TYPE}" = "all" ]; then
  log_section "Applying all policy types"
  for t in ${VALID_TYPES}; do apply_dir "${t}"; done
else
  case " ${VALID_TYPES} " in
    *" ${TYPE} "*) log_section "Applying policies/${TYPE}/"; apply_dir "${TYPE}" ;;
    *) log_fatal "Unknown policy type '${TYPE}'. Valid: ${VALID_TYPES} all" ;;
  esac
fi

log_info "Check results with: kubectl get clusterpolicies,policies -A"
