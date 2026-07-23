#!/usr/bin/env bash
# Guest provisioning step 02: kernel modules and sysctl settings required
# by the container runtime and Kubernetes networking (bridging, IP
# forwarding). Idempotent and persistent across reboots.
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
: "${NODE_NAME:?}"

log_section "02-configure-kernel: kernel modules and sysctls (${NODE_NAME})"

cat >/etc/modules-load.d/kubernetes.conf <<'EOF'
overlay
br_netfilter
EOF

for mod in overlay br_netfilter; do
  if ! is_kernel_module_loaded "${mod}"; then
    modprobe "${mod}"
    log_pass "Loaded kernel module: ${mod}"
  else
    log_info "Kernel module already loaded: ${mod}"
  fi
done

cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

for check in "net.bridge.bridge-nf-call-iptables=1" "net.bridge.bridge-nf-call-ip6tables=1" "net.ipv4.ip_forward=1"; do
  key="${check%%=*}"
  expected="${check##*=}"
  if is_sysctl_set "${key}" "${expected}"; then
    log_pass "sysctl ${key} = ${expected}"
  else
    log_fatal "sysctl ${key} did not apply (expected ${expected})"
  fi
done

# --- Firewall: UFW ships disabled by default on the bento/ubuntu-24.04
# box; we do not enable it (Kubernetes networking would need extensive,
# CNI-specific rules to work through UFW, which is out of scope for a
# host-only lab network). Document the actual state rather than assume it.
if command -v ufw >/dev/null 2>&1; then
  UFW_STATUS="$(ufw status 2>/dev/null | head -1)"
  log_info "UFW present, status: ${UFW_STATUS} (left as-is; see docs/NETWORKING.md)"
else
  log_info "UFW not installed on this image."
fi

log_pass "02-configure-kernel complete for ${NODE_NAME}."
