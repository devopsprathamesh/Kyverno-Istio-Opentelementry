#!/usr/bin/env bash
# Applies (and can reverse) controlled failure scenarios used by
# labs/lab-19-cilium-istio-troubleshooting.md. Every scenario is
# reversible via the same script with 'revert', and every scenario is
# scoped to DEMO_NAMESPACE only — never istio-system, never a real
# outage.
#
# Usage: inject-failures.sh <scenario> [apply|revert]
# Scenarios: block-dns, block-istiod, authz-deny, missing-sidecar
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
SCENARIO="${1:-}"
ACTION="${2:-apply}"
VALID_SCENARIOS="block-dns block-istiod authz-deny missing-sidecar"

if [ -z "${SCENARIO}" ]; then
  log_fatal "Usage: $0 <${VALID_SCENARIOS// /|}> [apply|revert]"
fi
if ! kube_reachable; then
  log_fatal "No reachable cluster. Run 'make verify-cluster' first."
fi

NAME="lab19-${SCENARIO}"

block_dns() {
  cat <<EOF | kubectl "$1" -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ${NAME}
  namespace: ${DEMO_NAMESPACE}
spec:
  endpointSelector: {}
  egressDeny:
    - toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
EOF
}

block_istiod() {
  cat <<EOF | kubectl "$1" -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: ${NAME}
  namespace: ${DEMO_NAMESPACE}
spec:
  endpointSelector: {}
  egressDeny:
    - toEntities: ["all"]
      toPorts:
        - ports:
            - port: "15012"
              protocol: TCP
EOF
}

authz_deny() {
  cat <<EOF | kubectl "$1" -f -
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: ${NAME}
  namespace: ${DEMO_NAMESPACE}
spec:
  selector:
    matchLabels: {app: order-service}
  action: DENY
  rules:
    - {}
EOF
}

missing_sidecar() {
  if [ "$1" = "apply" ]; then
    kubectl label namespace "${DEMO_NAMESPACE}" istio-injection- istio.io/rev- >/dev/null 2>&1 || true
    log_info "Removed injection labels from ${DEMO_NAMESPACE}. Restart a deployment (kubectl rollout restart) to see a pod come up WITHOUT a sidecar."
  else
    kubectl label namespace "${DEMO_NAMESPACE}" "istio.io/rev=${ISTIO_REVISION}" --overwrite >/dev/null
    log_info "Restored injection label on ${DEMO_NAMESPACE}. Restart deployments to re-inject sidecars."
  fi
}

log_section "Scenario: ${SCENARIO} (${ACTION})"
case "${SCENARIO}" in
  block-dns) [ "${ACTION}" = "apply" ] && block_dns apply || block_dns delete ;;
  block-istiod) [ "${ACTION}" = "apply" ] && block_istiod apply || block_istiod delete ;;
  authz-deny) [ "${ACTION}" = "apply" ] && authz_deny apply || authz_deny delete ;;
  missing-sidecar) missing_sidecar "${ACTION}" ;;
  *) log_fatal "Unknown scenario '${SCENARIO}'. Valid: ${VALID_SCENARIOS}" ;;
esac
log_pass "Scenario ${SCENARIO} ${ACTION} complete. See labs/lab-19-cilium-istio-troubleshooting.md for the diagnostic walkthrough."
