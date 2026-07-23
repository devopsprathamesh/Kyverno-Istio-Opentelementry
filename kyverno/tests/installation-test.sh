#!/usr/bin/env bash
# Runtime test: Kyverno installation health only (no functional probes —
# see scripts/validate-installation.sh for those). Lighter/faster,
# intended for repeated use while iterating on policies without
# re-running the full probe suite each time.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — installation-test skipped (not a failure; run 'make verify-cluster' for detail)."
  exit 0
fi

FAIL=0
check() {
  local d="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then log_pass "${d}"; else log_fail "${d}"; FAIL=1; fi
}

log_section "Installation health"
check "Namespace '${KYVERNO_NAMESPACE}' exists" -- namespace_exists "${KYVERNO_NAMESPACE}"
check "Helm release 'kyverno' exists" -- helm_release_exists kyverno "${KYVERNO_NAMESPACE}"
for deploy in kyverno-admission-controller kyverno-background-controller kyverno-cleanup-controller kyverno-reports-controller; do
  check "Deployment ${deploy} available" -- deployment_rollout_ready "${KYVERNO_NAMESPACE}" "${deploy}" 5
done
check "At least one validating webhook present" -- any_kyverno_webhook_exists validating
check "At least one mutating webhook present" -- any_kyverno_webhook_exists mutating

exit "${FAIL}"
