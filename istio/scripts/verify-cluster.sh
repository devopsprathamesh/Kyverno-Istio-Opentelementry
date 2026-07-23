#!/usr/bin/env bash
# Confirms a reachable Kubernetes cluster exists, is the intended local
# learning cluster, and has healthy Cilium/kube-proxy/CoreDNS — before
# any install/runtime-test script is allowed to proceed. This module
# never runs `vagrant`/`make setup` itself and never modifies Cilium.
#
# Identity is confirmed via API server endpoint, node count, and exact
# node names — not just "a cluster exists". A mismatch stops here with
# a clear report rather than silently installing into the wrong
# cluster. Per this phase's explicit rule, Istio is refused when: the
# API endpoint doesn't match, node names don't match, Cilium isn't
# healthy, or CoreDNS isn't healthy.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=./lib/istio.sh
source "${MODULE_ROOT}/scripts/lib/istio.sh"

log_section "Verifying cluster identity and networking prerequisites"

require_cmd kubectl
FAIL_COUNT=0
fail() { log_fail "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if ! kube_reachable; then
  fail "No reachable Kubernetes API server (kubectl get --raw=/healthz failed)."
  log_info "This module never creates a cluster itself. If you haven't provisioned the base platform yet, run:"
  log_info "  cd ../auto-setup-default-kube-env && make prerequisites && make setup LAB_PROFILE=recommended && make validate"
  log_info "  export KUBECONFIG=\"\$(cd ../auto-setup-default-kube-env && pwd)/.generated/kubeconfig\""
  exit 1
fi
log_pass "API server is reachable."

CONTEXT="$(current_context)"
API_SERVER="$(current_api_server)"
log_info "Current context: ${CONTEXT:-<none>}"
log_info "Current API server: ${API_SERVER:-<unknown>}"

if [ -z "${API_SERVER}" ] || [[ "${API_SERVER}" != *"${EXPECTED_API_ENDPOINT}"* ]]; then
  fail "API server '${API_SERVER:-<unknown>}' does not reference the expected endpoint '${EXPECTED_API_ENDPOINT}'. This does not look like the intended local lab cluster — refusing to proceed. If this is genuinely a different, unrelated cluster, this module must not be installed into it."
else
  log_pass "API server references the expected endpoint (${EXPECTED_API_ENDPOINT})."
fi

ACTUAL_NODES="$(node_names)"
for expected in "${EXPECTED_CONTROL_PLANE_NAME}" "${EXPECTED_WORKER1_NAME}" "${EXPECTED_WORKER2_NAME}"; do
  if ! grep -qw -- "${expected}" <<<"${ACTUAL_NODES}"; then
    fail "Expected node '${expected}' not found in cluster node list: ${ACTUAL_NODES}"
  fi
done
[ "${FAIL_COUNT}" -eq 0 ] && log_pass "All 3 expected nodes present: ${ACTUAL_NODES}"

log_section "Networking health (Cilium, kube-proxy, CoreDNS)"

if daemonset_ready kube-system cilium; then
  log_pass "Cilium DaemonSet is healthy (all desired pods Ready)."
else
  fail "Cilium DaemonSet is not healthy — refusing to proceed. Check 'kubectl -n kube-system get daemonset cilium' and 'cilium status' on the control plane."
fi

if resource_exists daemonset kube-proxy kube-system; then
  log_pass "kube-proxy DaemonSet present (retained, as expected — see root docs/DECISIONS.md ADR-003/ADR-021)."
else
  log_warn "kube-proxy DaemonSet not found — if this cluster has kube-proxy replacement enabled, that is an advanced profile this lab was not validated against (root docs/DECISIONS.md ADR-003)."
fi

if daemonset_ready kube-system coredns 2>/dev/null || deployment_rollout_ready kube-system coredns 5 2>/dev/null; then
  log_pass "CoreDNS is healthy."
else
  fail "CoreDNS does not appear healthy — refusing to proceed. Check 'kubectl -n kube-system get pods -l k8s-app=kube-dns'."
fi

log_section "Cilium + Istio CNI-chaining compatibility (informational — see docs/04-istio-cni-and-cilium.md)"
if command -v helm >/dev/null 2>&1; then
  if cilium_cni_chaining_ready; then
    log_pass "Live Cilium release already has the values Istio CNI chaining requires."
  else
    print_cilium_cni_chaining_remediation
    log_warn "Proceeding past this check (verify-cluster only warns here) — 'make install' will hard-refuse the Istio CNI installation step specifically if this is still unresolved, since that is where it would actually fail."
  fi
else
  log_warn "helm not installed — cannot check live Cilium values for CNI-chaining compatibility. See docs/04-istio-cni-and-cilium.md."
fi

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "Cluster verification failed: ${FAIL_COUNT} mandatory check(s) did not pass. Refusing to install Istio into this cluster."
  exit 1
fi
log_pass "Cluster identity and networking prerequisites confirmed: this is the intended local learning cluster (${EXPECTED_CLUSTER_NAME})."
