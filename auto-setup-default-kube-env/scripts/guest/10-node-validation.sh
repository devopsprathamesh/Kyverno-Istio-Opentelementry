#!/usr/bin/env bash
# Guest provisioning step 10: final per-node validation, run on every
# node (control plane and both workers) at the end of its provisioning
# sequence. Prints PASS/WARN/FAIL lines; does not fail the overall
# `vagrant up` on a WARN, but does on a FAIL — matching this module's
# convention of failing only mandatory checks.
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
: "${NODE_NAME:?}"
: "${NODE_ROLE:?}"

log_section "10-node-validation: OS + Kubernetes layer checks (${NODE_NAME})"

FAIL_COUNT=0

check() {
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then
    log_pass "${description}"
  else
    log_fail "${description}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

check "Swap is disabled" is_swap_disabled
check "Kernel module overlay loaded" is_kernel_module_loaded overlay
check "Kernel module br_netfilter loaded" is_kernel_module_loaded br_netfilter
check "sysctl net.ipv4.ip_forward=1" is_sysctl_set net.ipv4.ip_forward 1
check "containerd is active" is_containerd_active
check "kubelet is installed" is_kubelet_installed
check "This node has joined/initialized the cluster (kubelet.conf present)" is_node_joined

log_info "Disk: $(df -h / | tail -1)"
log_info "Memory: $(free -h | grep Mem)"

if [ "${NODE_ROLE}" = "control-plane" ] && [ -f /etc/kubernetes/admin.conf ]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
  log_info "Cluster node summary:"
  kubectl get nodes -o wide || log_warn "Could not list nodes from control plane."
fi

if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "10-node-validation: ${FAIL_COUNT} mandatory check(s) failed on ${NODE_NAME}."
  exit 1
fi

log_pass "10-node-validation complete for ${NODE_NAME}: all mandatory checks passed."
