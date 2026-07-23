#!/usr/bin/env bash
# Runtime test: the demo Gateway/VirtualService actually route external
# (port-forwarded) traffic to the frontend service.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — ingress-test skipped."
  exit 0
fi

log_section "ingress-test"

PF_PID=""
cleanup() { [ -n "${PF_PID}" ] && kill "${PF_PID}" 2>/dev/null || true; }
trap cleanup EXIT

kubectl -n "${ISTIO_INGRESS_NAMESPACE}" port-forward svc/istio-ingress "${INGRESS_GATEWAY_LOCAL_PORT}:${INGRESS_GATEWAY_SERVICE_PORT}" >/tmp/istio-lab-ingress-pf.log 2>&1 &
PF_PID=$!
sleep 3

if curl -fsS -H "Host: frontend.istio-lab.local" "http://localhost:${INGRESS_GATEWAY_LOCAL_PORT}/" --max-time 5 | grep -qi "frontend"; then
  log_pass "Ingress gateway routed a request to frontend successfully."
  exit 0
else
  log_fail "Ingress gateway did not route the request as expected. Port-forward log:"
  cat /tmp/istio-lab-ingress-pf.log || true
  exit 1
fi
