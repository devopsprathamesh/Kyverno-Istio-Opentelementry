#!/usr/bin/env bash
# Guest provisioning step 04: install pinned kubeadm/kubelet/kubectl from
# the official Kubernetes community package repository (pkgs.k8s.io —
# the legacy apt.kubernetes.io repository is deprecated/removed).
# Idempotent; holds packages against unintended upgrades.
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
: "${NODE_NAME:?}"

log_section "04-install-kubernetes: kubeadm/kubelet/kubectl ${KUBERNETES_VERSION} (${NODE_NAME})"

KUBELET_VERSION_OUTPUT="$(kubelet --version 2>/dev/null || true)"
if is_kubelet_installed && grep -q "${KUBERNETES_VERSION}" <<<"${KUBELET_VERSION_OUTPUT}"; then
  log_info "kubelet ${KUBERNETES_VERSION} already installed, skipping."
else
  export DEBIAN_FRONTEND=noninteractive
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "${KUBERNETES_APT_KEY}" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] ${KUBERNETES_APT_REPO} /" \
    >/etc/apt/sources.list.d/kubernetes.list
  apt-get update -y

  apt-get install -y --no-install-recommends \
    "kubelet=${KUBERNETES_PKG_VERSION}" \
    "kubeadm=${KUBERNETES_PKG_VERSION}" \
    "kubectl=${KUBERNETES_PKG_VERSION}"
  apt-mark hold kubelet kubeadm kubectl
  log_pass "kubelet/kubeadm/kubectl ${KUBERNETES_PKG_VERSION} installed and held."
fi

systemctl enable kubelet
# kubelet is expected to crashloop / repeatedly restart here — it has no
# cluster config yet (no /var/lib/kubelet/config.yaml) until kubeadm
# init/join runs in the next step. This is normal, not a failure signal
# at this point in provisioning.
systemctl start kubelet || true

log_info "Validation: kubeadm version -> $(kubeadm version -o short 2>/dev/null || true)"
log_info "Validation: kubelet --version -> $(kubelet --version 2>/dev/null || true)"
log_info "Validation: kubectl version --client -> $(kubectl version --client 2>/dev/null || true)"
log_info "Validation: apt-mark showhold -> $(apt-mark showhold | tr '\n' ' ')"
log_info "Validation: kubelet unit state (expected to be activating/restarting pre-init) -> $(systemctl is-active kubelet || true)"

log_pass "04-install-kubernetes complete for ${NODE_NAME}."
