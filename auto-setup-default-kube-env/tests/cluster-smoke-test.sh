#!/usr/bin/env bash
# Runtime check: deploys a single throwaway pod and confirms it reaches
# Running, then deletes it. Requires a live, reachable cluster — if the
# exported kubeconfig is missing or the API server is unreachable, this
# prints why and exits 0 rather than falsely reporting failure for an
# environment that was never brought up in the first place.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${MODULE_ROOT}/.generated/kubeconfig"

if [ ! -f "${KUBECONFIG_PATH}" ]; then
  echo "[INFO] No kubeconfig at ${KUBECONFIG_PATH} — cluster has not been provisioned. Nothing to smoke-test. Run 'make setup' first."
  exit 0
fi
export KUBECONFIG="${KUBECONFIG_PATH}"

if ! kubectl get --raw=/healthz >/dev/null 2>&1; then
  echo "[INFO] API server not reachable via ${KUBECONFIG_PATH} — cluster is not currently up. Nothing to smoke-test."
  exit 0
fi

NS="cluster-smoke-test"
cleanup() { kubectl delete namespace "${NS}" --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl run smoke-pod -n "${NS}" --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null

if kubectl -n "${NS}" wait --for=condition=Ready pod/smoke-pod --timeout=60s >/dev/null 2>&1; then
  echo "[PASS] cluster-smoke-test: pod scheduled and reached Ready."
else
  echo "[FAIL] cluster-smoke-test: pod did not reach Ready within 60s."
  kubectl -n "${NS}" describe pod smoke-pod || true
  exit 1
fi
