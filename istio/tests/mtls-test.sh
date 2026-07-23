#!/usr/bin/env bash
# Runtime test: strict mTLS actually rejects a plaintext connection
# from a non-mesh (no sidecar) client, while an in-mesh client still
# succeeds.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — mtls-test skipped."
  exit 0
fi

log_section "mtls-test"

cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/peerauthentication/strict.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl apply -f "${MODULE_ROOT}/policies/peerauthentication/permissive.yaml" >/dev/null 2>&1 || true
  kubectl -n "${DEMO_NAMESPACE}" delete pod mtls-plaintext-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply -f "${MODULE_ROOT}/policies/peerauthentication/strict.yaml" >/dev/null
sleep 5

# In-mesh client (test-client.yaml, sidecar-injected) should succeed.
if kubectl -n "${DEMO_NAMESPACE}" get pod test-client >/dev/null 2>&1; then
  if kubectl -n "${DEMO_NAMESPACE}" exec test-client -c curl -- curl -fsS -o /dev/null --max-time 5 http://frontend/ 2>/dev/null; then
    log_pass "In-mesh (sidecar-injected) client succeeded under STRICT mTLS."
  else
    log_fail "In-mesh client failed under STRICT mTLS — unexpected."
    exit 1
  fi
else
  log_warn "demo/security/test-client.yaml was not deployed — apply it first ('kubectl apply -f demo/security/test-client.yaml'). Skipping the in-mesh success check."
fi

# A pod explicitly excluded from injection (no sidecar) simulates a
# plaintext, non-mesh client and should be rejected.
kubectl run mtls-plaintext-client -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" \
  --annotations="sidecar.istio.io/inject=false" \
  --command -- sleep 60 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready pod/mtls-plaintext-client --timeout=60s >/dev/null

if kubectl -n "${DEMO_NAMESPACE}" exec mtls-plaintext-client -- curl -fsS -o /dev/null --max-time 5 http://frontend/ 2>/dev/null; then
  log_fail "Plaintext (non-mesh) client succeeded under STRICT mTLS — expected rejection."
  exit 1
else
  log_pass "Plaintext (non-mesh) client was correctly rejected under STRICT mTLS."
  exit 0
fi
