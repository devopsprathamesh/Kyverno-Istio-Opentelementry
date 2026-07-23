#!/usr/bin/env bash
# Creates istio-demo (sidecar-injection labeled) and istio-external,
# then deploys the demo microservices app (frontend -> order-service ->
# {inventory-service, payment-service}) and the ingress Gateway. Does
# NOT apply traffic/security/resilience/egress policies — those are
# applied per-lab so learners see each concept's effect in isolation.
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

log_section "Deploying demo application to ${DEMO_NAMESPACE}"

kubectl apply -f "${MODULE_ROOT}/demo/namespace.yaml"
log_pass "Namespaces ${DEMO_NAMESPACE}/${EXTERNAL_NAMESPACE} ensured (labeled for sidecar injection)."

for svc in frontend order-service inventory-service payment-service; do
  path="${MODULE_ROOT}/demo/services/${svc}"
  if [ -d "${path}" ] && [ -n "$(find "${path}" -maxdepth 1 -name '*.yaml' 2>/dev/null)" ]; then
    kubectl apply -f "${path}"
    log_pass "Deployed demo/services/${svc}/"
  fi
done

if [ -d "${MODULE_ROOT}/demo/gateway" ] && [ -n "$(find "${MODULE_ROOT}/demo/gateway" -maxdepth 1 -name '*.yaml' 2>/dev/null)" ]; then
  kubectl apply -f "${MODULE_ROOT}/demo/gateway"
  log_pass "Applied demo/gateway/ (ingress Gateway + base VirtualService)."
fi

wait_for "frontend Deployment available" 120 5 -- deployment_rollout_ready "${DEMO_NAMESPACE}" frontend-v1 5

log_info "Access: make -C \"${MODULE_ROOT}\" status  (or port-forward the ingress gateway — see examples/application-access.md)"
log_pass "Demo deployment complete."
