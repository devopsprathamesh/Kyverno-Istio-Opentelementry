#!/usr/bin/env bash
# Sets payment-service's configurable latency env var and rolls the
# Deployment, producing slow traces on demand. Usage:
#   inject-latency.sh [MS] [apply|revert]
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

MS="${1:-1500}"
ACTION="${2:-apply}"

if [ "${ACTION}" = "revert" ]; then
  MS="${DEMO_DEFAULT_LATENCY_MS}"
fi

log_section "Setting payment-service LATENCY_MS=${MS} (${ACTION})"
kubectl -n "${OTEL_DEMO_NAMESPACE}" set env deployment/payment-service "LATENCY_MS=${MS}"
kubectl -n "${OTEL_DEMO_NAMESPACE}" rollout status deployment/payment-service --timeout="${INSTALL_WAIT_TIMEOUT_SECONDS}s"
log_pass "payment-service now injects ${MS}ms of latency per request. Revert with: $0 0 revert"
