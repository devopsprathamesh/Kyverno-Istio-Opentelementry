#!/usr/bin/env bash
# Confirms a reachable Kubernetes cluster exists AND that it is the
# intended local learning cluster from ../auto-setup-default-kube-env,
# before any install/runtime-test script is allowed to proceed. This
# module never runs `vagrant`/`make setup` itself — it only checks.
#
# Identity is confirmed via: API server endpoint, node count, and exact
# node names — not just "a cluster exists". A mismatch stops here with
# a clear report rather than silently installing into the wrong cluster.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

log_section "Verifying cluster identity"

require_cmd kubectl

if ! kube_reachable; then
  log_fail "No reachable Kubernetes API server (kubectl get --raw=/healthz failed)."
  log_info "This module never creates a cluster itself. If you haven't provisioned the base platform yet, run:"
  log_info "  cd ../auto-setup-default-kube-env && make prerequisites && make setup LAB_PROFILE=recommended && make validate"
  log_info "  export KUBECONFIG=\"\$(cd ../auto-setup-default-kube-env && pwd)/.generated/kubeconfig\""
  log_info "If the base platform IS up, confirm KUBECONFIG points at it: echo \$KUBECONFIG"
  exit 1
fi
log_pass "API server is reachable."

CONTEXT="$(current_context)"
API_SERVER="$(current_api_server)"
log_info "Current context: ${CONTEXT:-<none>}"
log_info "Current API server: ${API_SERVER:-<unknown>}"

if [ -z "${API_SERVER}" ] || [[ "${API_SERVER}" != *"${EXPECTED_API_ENDPOINT}"* ]]; then
  log_fail "API server '${API_SERVER:-<unknown>}' does not reference the expected endpoint '${EXPECTED_API_ENDPOINT}' (auto-setup-default-kube-env's otel-control-plane). Refusing to install Kyverno into an unrecognized cluster."
  exit 1
fi
log_pass "API server references the expected endpoint (${EXPECTED_API_ENDPOINT})."

ACTUAL_NODES="$(node_names)"
MISSING=0
for expected in "${EXPECTED_CONTROL_PLANE_NAME}" "${EXPECTED_WORKER1_NAME}" "${EXPECTED_WORKER2_NAME}"; do
  if ! grep -qw -- "${expected}" <<<"${ACTUAL_NODES}"; then
    log_fail "Expected node '${expected}' not found in cluster node list: ${ACTUAL_NODES}"
    MISSING=$((MISSING + 1))
  fi
done

if [ "${MISSING}" -gt 0 ]; then
  log_fail "Cluster identity mismatch: ${MISSING} expected node(s) missing. Refusing to proceed. See docs/14-troubleshooting.md if this is unexpected."
  exit 1
fi
log_pass "All 3 expected nodes present: ${ACTUAL_NODES}"

NODE_COUNT="$(wc -w <<<"${ACTUAL_NODES}")"
if [ "${NODE_COUNT}" -ne 3 ]; then
  log_warn "Cluster has ${NODE_COUNT} nodes, not exactly 3 — proceeding, since the 3 expected nodes are present, but this differs from the documented base-platform topology."
fi

log_pass "Cluster identity confirmed: this is the intended local learning cluster (${EXPECTED_CLUSTER_NAME})."
