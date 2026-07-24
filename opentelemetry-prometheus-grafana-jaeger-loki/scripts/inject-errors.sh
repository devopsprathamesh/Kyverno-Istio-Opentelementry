#!/usr/bin/env bash
# Sets payment-service's configurable failure-percentage env var and
# rolls the Deployment, producing failed traces/error logs on demand.
# Usage: inject-errors.sh [PERCENT] [apply|revert]
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
if ! kube_reachable; then
  log_fatal "No reachable cluster. Run 'make verify-cluster' first."
fi

PERCENT="${1:-30}"
ACTION="${2:-apply}"

if [ "${ACTION}" = "revert" ]; then
  PERCENT="${DEMO_DEFAULT_FAILURE_PERCENT}"
fi

log_section "Setting payment-service FAILURE_PERCENT=${PERCENT} (${ACTION})"
kubectl -n "${OTEL_DEMO_NAMESPACE}" set env deployment/payment-service "FAILURE_PERCENT=${PERCENT}"
kubectl -n "${OTEL_DEMO_NAMESPACE}" rollout status deployment/payment-service --timeout="${INSTALL_WAIT_TIMEOUT_SECONDS}s"
log_pass "payment-service now fails approximately ${PERCENT}% of requests. Revert with: $0 0 revert"
