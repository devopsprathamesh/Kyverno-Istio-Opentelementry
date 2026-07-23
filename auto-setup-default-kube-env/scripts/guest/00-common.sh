#!/usr/bin/env bash
# Guest provisioning step 00: baseline OS setup shared by every node
# (control plane and workers alike). Run as root via Vagrant's shell
# provisioner. Idempotent: safe to re-run on `vagrant provision`.
#
# Execution order across all guest scripts is fixed by the Vagrantfile,
# not by these filenames' numeric prefixes — see Vagrantfile comments
# and docs/INSTALLATION.md for the actual per-role sequence (Helm, in
# particular, runs before Cilium despite 09 sorting after 06).
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
ensure_generated_dirs

: "${NODE_NAME:?NODE_NAME must be set by the Vagrantfile provisioner}"
: "${NODE_ROLE:?NODE_ROLE must be set by the Vagrantfile provisioner}"
: "${NODE_IP:?NODE_IP must be set by the Vagrantfile provisioner}"

log_section "00-common: hostname, /etc/hosts, base packages, swap, time sync (${NODE_NAME})"

# --- Proxy support: only configure anything if the caller set proxy vars.
HTTP_PROXY="${HTTP_PROXY:-${http_proxy:-}}"
HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
NO_PROXY="${NO_PROXY:-${no_proxy:-}}"
GENERATED_NO_PROXY="localhost,127.0.0.1,${CONTROL_PLANE_IP},${WORKER1_IP},${WORKER2_IP},${SERVICE_SUBNET},${CILIUM_CLUSTER_POOL_CIDR},.svc,.cluster.local"
if [ -n "${NO_PROXY}" ]; then
  NO_PROXY="${NO_PROXY},${GENERATED_NO_PROXY}"
else
  NO_PROXY="${GENERATED_NO_PROXY}"
fi

if [ -n "${HTTP_PROXY}" ] || [ -n "${HTTPS_PROXY}" ]; then
  log_info "Proxy variables detected — configuring apt proxy."
  {
    [ -n "${HTTP_PROXY}" ] && printf 'Acquire::http::Proxy "%s";\n' "${HTTP_PROXY}"
    [ -n "${HTTPS_PROXY}" ] && printf 'Acquire::https::Proxy "%s";\n' "${HTTPS_PROXY}"
  } >/etc/apt/apt.conf.d/95proxy
else
  log_info "No proxy variables set — skipping proxy configuration."
  rm -f /etc/apt/apt.conf.d/95proxy
fi

# --- Stable hostname -----------------------------------------------------
if [ "$(hostname)" != "${NODE_NAME}" ]; then
  hostnamectl set-hostname "${NODE_NAME}"
  log_pass "Hostname set to ${NODE_NAME}"
else
  log_info "Hostname already ${NODE_NAME}, skipping."
fi

# --- /etc/hosts for all three nodes --------------------------------------
HOSTS_MARKER_BEGIN="# BEGIN auto-setup-default-kube-env"
HOSTS_MARKER_END="# END auto-setup-default-kube-env"
if ! grep -q "${HOSTS_MARKER_BEGIN}" /etc/hosts 2>/dev/null; then
  {
    echo "${HOSTS_MARKER_BEGIN}"
    echo "${CONTROL_PLANE_IP} ${CONTROL_PLANE_NAME}"
    echo "${WORKER1_IP} ${WORKER1_NAME}"
    echo "${WORKER2_IP} ${WORKER2_NAME}"
    echo "${HOSTS_MARKER_END}"
  } >>/etc/hosts
  log_pass "/etc/hosts entries added for all three nodes."
else
  log_info "/etc/hosts entries already present, skipping."
fi

# --- Base packages ---------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg apt-transport-https software-properties-common \
  gettext-base chrony conntrack socat

# --- Time synchronization -------------------------------------------------
systemctl enable --now chrony >/dev/null 2>&1 || true
if command -v chronyc >/dev/null 2>&1; then
  retry 5 3 -- chronyc waitsync 5 0.5 || log_warn "chrony did not confirm sync within retries; continuing (VirtualBox host time sync usually compensates)."
fi

# --- Swap: disable immediately and persistently ---------------------------
if ! is_swap_disabled; then
  swapoff -a
  log_pass "Swap disabled for this session."
else
  log_info "Swap already disabled."
fi
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

log_info "Validation: swapon --show -> $(swapon --show || true)"
log_info "Validation: timedatectl status -> $(timedatectl status | grep -i 'synchronized\|ntp' || true)"

echo "${NO_PROXY}" >"${GENERATED_DIR}/no-proxy.txt"
log_pass "00-common complete for ${NODE_NAME}."
