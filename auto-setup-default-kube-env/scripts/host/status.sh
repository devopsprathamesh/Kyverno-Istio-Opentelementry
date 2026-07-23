#!/usr/bin/env bash
# Quick, read-only status summary: VM state, node readiness, Cilium/
# Hubble health, storage. Faster and less exhaustive than
# validate-cluster.sh — meant for a quick glance, not a pass/fail gate.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

require_not_root
cd "${MODULE_ROOT}"

log_section "VM status"
vagrant status || true

KUBECONFIG_PATH="${GENERATED_DIR}/kubeconfig"
if [ -f "${KUBECONFIG_PATH}" ] && command -v kubectl >/dev/null 2>&1; then
  export KUBECONFIG="${KUBECONFIG_PATH}"
  log_section "Nodes"
  kubectl get nodes -o wide 2>/dev/null || log_warn "Could not reach the API server."

  log_section "Cilium / Hubble"
  kubectl -n "${CILIUM_NAMESPACE}" get pods -l k8s-app=cilium -o wide 2>/dev/null || true
  kubectl -n "${CILIUM_NAMESPACE}" get deployment cilium-operator hubble-relay 2>/dev/null || true

  log_section "Storage"
  kubectl get storageclass 2>/dev/null || true
else
  log_info "No kubeconfig yet at ${KUBECONFIG_PATH} — cluster has not been set up, or export-kubeconfig hasn't run."
fi
