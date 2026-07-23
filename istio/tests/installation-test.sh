#!/usr/bin/env bash
# Runtime test: Istio installation health only (no functional probes —
# see scripts/validate-installation.sh for those). Lighter/faster,
# intended for repeated use while iterating without re-running the
# full probe suite each time.
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
check "Namespace '${ISTIO_SYSTEM_NAMESPACE}' exists" -- namespace_exists "${ISTIO_SYSTEM_NAMESPACE}"
check "Namespace '${ISTIO_INGRESS_NAMESPACE}' exists" -- namespace_exists "${ISTIO_INGRESS_NAMESPACE}"
for release in istio-base istiod istio-cni; do
  check "Helm release '${release}' exists" -- helm_release_exists "${release}" "${ISTIO_SYSTEM_NAMESPACE}"
done
check "Helm release 'istio-ingress' exists" -- helm_release_exists istio-ingress "${ISTIO_INGRESS_NAMESPACE}"
check "Istio CNI DaemonSet healthy" -- daemonset_ready "${ISTIO_SYSTEM_NAMESPACE}" istio-cni-node
check "Ingress gateway deployment available" -- deployment_rollout_ready "${ISTIO_INGRESS_NAMESPACE}" istio-ingress 5

exit "${FAIL}"
