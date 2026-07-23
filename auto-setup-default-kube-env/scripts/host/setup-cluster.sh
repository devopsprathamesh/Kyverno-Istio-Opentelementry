#!/usr/bin/env bash
# Explicit, ordered cluster setup — does not rely on Vagrant's own
# multi-VM ordering/parallelism behavior. Invoked by `make setup`.
#
# Order: control plane (which internally runs Helm -> kubeadm init ->
# Cilium/Hubble) -> worker 1 -> worker 2 -> storage -> validation.
#
# Usage: scripts/host/setup-cluster.sh [minimum|recommended]
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

require_not_root
LAB_PROFILE="${1:-${LAB_PROFILE:-${DEFAULT_LAB_PROFILE}}}"
export LAB_PROFILE

case " ${VALID_LAB_PROFILES} " in
  *" ${LAB_PROFILE} "*) ;;
  *) log_fatal "Invalid LAB_PROFILE='${LAB_PROFILE}'. Valid values: ${VALID_LAB_PROFILES}" ;;
esac

cd "${MODULE_ROOT}"

log_section "setup-cluster: profile=${LAB_PROFILE}"

log_info "Step 1/6: prerequisite check"
"${MODULE_ROOT}/scripts/host/check-prerequisites.sh" "${LAB_PROFILE}"

log_info "Step 2/6: control plane (VM boot -> OS/kernel/containerd/kubernetes -> Helm -> kubeadm init -> Cilium/Hubble)"
vagrant up "${CONTROL_PLANE_NAME}"

log_info "Step 3/6: worker 1 join"
vagrant up "${WORKER1_NAME}"

log_info "Step 4/6: worker 2 join"
vagrant up "${WORKER2_NAME}"

log_info "Step 5/6: storage (deferred until both workers exist so PVC test pods are schedulable)"
vagrant ssh "${CONTROL_PLANE_NAME}" -c "sudo NODE_NAME=${CONTROL_PLANE_NAME} NODE_ROLE=control-plane bash /vagrant/scripts/guest/08-install-storage.sh"

log_info "Step 6/6: host-side kubeconfig export and cluster validation"
"${MODULE_ROOT}/scripts/host/export-kubeconfig.sh"
"${MODULE_ROOT}/scripts/host/validate-cluster.sh"

log_pass "setup-cluster complete for profile '${LAB_PROFILE}'."
log_info "Next: export KUBECONFIG=\"${MODULE_ROOT}/.generated/kubeconfig\" && kubectl get nodes -o wide"
