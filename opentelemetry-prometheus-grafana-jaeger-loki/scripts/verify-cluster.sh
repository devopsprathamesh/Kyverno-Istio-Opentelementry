#!/usr/bin/env bash
# Confirms a reachable Kubernetes cluster exists, is the intended local
# learning cluster, and has healthy Cilium/kube-proxy/CoreDNS/storage —
# before any install/runtime-test script is allowed to proceed. This
# module never runs `vagrant`/`make setup` itself and never modifies
# Cilium, kube-proxy, or any other module's resources.
#
# Identity is confirmed via API server endpoint, node count, and exact
# node names — not just "a cluster exists". A mismatch stops here with
# a clear report rather than silently installing into the wrong
# cluster.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

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

ACTUAL_NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}' || true)"
if [ -n "${ACTUAL_NOT_READY}" ]; then
  fail "Node(s) not Ready: ${ACTUAL_NOT_READY}"
else
  log_pass "All nodes report Ready."
fi

log_section "Networking and storage health (Cilium, kube-proxy, CoreDNS, StorageClass)"

if daemonset_ready kube-system cilium; then
  log_pass "Cilium DaemonSet is healthy (all desired pods Ready)."
else
  fail "Cilium DaemonSet is not healthy — refusing to proceed. Check 'kubectl -n kube-system get daemonset cilium' and 'cilium status' on the control plane."
fi

if resource_exists daemonset kube-proxy kube-system; then
  log_pass "kube-proxy DaemonSet present (retained, as expected — see root docs/DECISIONS.md ADR-003)."
else
  log_warn "kube-proxy DaemonSet not found — if this cluster has kube-proxy replacement enabled, that is an advanced profile this lab was not validated against (root docs/DECISIONS.md ADR-003)."
fi

if daemonset_ready kube-system coredns 2>/dev/null || deployment_rollout_ready kube-system coredns 5 2>/dev/null; then
  log_pass "CoreDNS is healthy."
else
  fail "CoreDNS does not appear healthy — refusing to proceed. Check 'kubectl -n kube-system get pods -l k8s-app=kube-dns'."
fi

STORAGECLASSES="$(kubectl get storageclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
if [ -n "${STORAGECLASSES}" ]; then
  log_pass "At least one StorageClass is available (${STORAGECLASSES}) — required for Prometheus/Loki/Grafana PVCs in the 'recommended' profile."
else
  fail "No StorageClass found — Prometheus/Loki/Grafana PVCs will not bind. Confirm ../auto-setup-default-kube-env's local-path-provisioner installed correctly."
fi

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "Cluster verification failed: ${FAIL_COUNT} mandatory check(s) did not pass. Refusing to install the observability stack into this cluster."
  exit 1
fi
log_pass "Cluster identity, networking, and storage prerequisites confirmed: this is the intended local learning cluster (${EXPECTED_CLUSTER_NAME})."
