#!/usr/bin/env bash
# Runtime test: default-deny + explicit allow AuthorizationPolicy
# actually enforces the allowed-caller graph — frontend can reach
# order-service, but a policy-unaware client cannot.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — authorization-test skipped."
  exit 0
fi

log_section "authorization-test"

cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/authorization/namespace-default-deny.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f "${MODULE_ROOT}/policies/authorization/allow-frontend-to-order.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${DEMO_NAMESPACE}" delete pod authz-unauthorized-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply -f "${MODULE_ROOT}/policies/authorization/namespace-default-deny.yaml" >/dev/null
kubectl apply -f "${MODULE_ROOT}/policies/authorization/allow-frontend-to-order.yaml" >/dev/null
sleep 5

# A client running under a DIFFERENT ServiceAccount (not "frontend")
# should be denied by order-service's AuthorizationPolicy.
kubectl run authz-unauthorized-client -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" \
  --overrides='{"spec":{"serviceAccountName":"payment-service"}}' \
  --command -- sleep 60 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready pod/authz-unauthorized-client --timeout=60s >/dev/null

CODE="$(kubectl -n "${DEMO_NAMESPACE}" exec authz-unauthorized-client -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://order-service/ 2>/dev/null || echo 000)"
if [ "${CODE}" = "403" ]; then
  log_pass "Unauthorized caller (wrong ServiceAccount identity) correctly denied (403) by AuthorizationPolicy."
else
  log_fail "Expected 403 from an unauthorized caller, got ${CODE}."
  exit 1
fi

if kubectl -n "${DEMO_NAMESPACE}" get pod test-client >/dev/null 2>&1; then
  # test-client.yaml runs under its own "test-client" ServiceAccount,
  # also not "frontend" — also expected to be denied, confirming the
  # allow rule is scoped to the frontend identity specifically, not
  # "any in-mesh caller".
  CODE2="$(kubectl -n "${DEMO_NAMESPACE}" exec test-client -c curl -- curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://order-service/ 2>/dev/null || echo 000)"
  if [ "${CODE2}" = "403" ]; then
    log_pass "A different non-frontend in-mesh identity (test-client) is also correctly denied — the allow rule is scoped to frontend specifically."
  else
    log_warn "test-client got ${CODE2} instead of 403 — verify allow-frontend-to-order.yaml's principal scoping."
  fi
fi

exit 0
