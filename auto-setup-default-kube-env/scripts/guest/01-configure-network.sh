#!/usr/bin/env bash
# Guest provisioning step 01: confirm the host-only interface has the
# expected private IP, and pin kubelet's advertised node IP to it so
# neither the API server nor kubelet ever advertise the NAT interface.
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
: "${NODE_NAME:?}"
: "${NODE_IP:?}"

log_section "01-configure-network: verifying host-only IP and pinning kubelet node-ip (${NODE_NAME})"

CURRENT_ADDRS="$(ip -4 addr show)"
# Captured before matching (not piped straight into `grep -q`) to avoid a
# SIGPIPE-under-`pipefail` false negative on a multi-interface host — see
# the equivalent comment in scripts/lib/validation.sh::is_kernel_module_loaded.
if grep -q "inet ${NODE_IP}/" <<<"${CURRENT_ADDRS}"; then
  log_pass "Host-only interface carries the expected IP ${NODE_IP}."
else
  log_fatal "Expected IP ${NODE_IP} not found on any interface. 'ip -4 addr show' output:\n$(ip -4 addr show)"
fi

# kubeadm's kubelet systemd drop-in (10-kubeadm.conf) sources
# /etc/default/kubelet via EnvironmentFile=- (optional, last-wins), which
# is the standard, documented mechanism for pinning kubelet's --node-ip
# without hand-editing the systemd unit. This is honored on both the
# control-plane (in addition to the belt-and-suspenders kubeletExtraArgs
# already set in config/kubeadm-config.yaml.tpl's InitConfiguration) and
# on workers (which have no equivalent InitConfiguration).
cat >/etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS="--node-ip=${NODE_IP}"
EOF
log_pass "/etc/default/kubelet written with --node-ip=${NODE_IP}."

log_info "01-configure-network complete for ${NODE_NAME}."
