#!/usr/bin/env bash
# Deploys the demo microservices app + load generator to otel-demo.
# Assumes 'make build-demo-images' has already imported the images into
# every node's containerd (manifests use imagePullPolicy: Never).
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

log_section "Deploying demo application to ${OTEL_DEMO_NAMESPACE}"

kubectl apply -f "${MODULE_ROOT}/install/namespaces/"

for svc in frontend order-service inventory-service payment-service load-generator; do
  path="${MODULE_ROOT}/demo-application/kubernetes/${svc}"
  if [ -d "${path}" ]; then
    kubectl apply -f "${path}"
    log_pass "Deployed demo-application/kubernetes/${svc}/"
  fi
done

wait_for "frontend Deployment available" "${INSTALL_WAIT_TIMEOUT_SECONDS}" 5 -- deployment_rollout_ready "${OTEL_DEMO_NAMESPACE}" frontend "${INSTALL_WAIT_TIMEOUT_SECONDS}"
wait_for "order-service Deployment available" "${INSTALL_WAIT_TIMEOUT_SECONDS}" 5 -- deployment_rollout_ready "${OTEL_DEMO_NAMESPACE}" order-service "${INSTALL_WAIT_TIMEOUT_SECONDS}"
wait_for "inventory-service Deployment available" "${INSTALL_WAIT_TIMEOUT_SECONDS}" 5 -- deployment_rollout_ready "${OTEL_DEMO_NAMESPACE}" inventory-service "${INSTALL_WAIT_TIMEOUT_SECONDS}"
wait_for "payment-service Deployment available" "${INSTALL_WAIT_TIMEOUT_SECONDS}" 5 -- deployment_rollout_ready "${OTEL_DEMO_NAMESPACE}" payment-service "${INSTALL_WAIT_TIMEOUT_SECONDS}"

log_info "Access: make status  (or port-forward the frontend — see examples/application-access.md)"
log_pass "Demo deployment complete. Run 'make generate-load' to produce traces/metrics/logs."
