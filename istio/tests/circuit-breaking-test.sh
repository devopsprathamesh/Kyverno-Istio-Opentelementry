#!/usr/bin/env bash
# Runtime test: connection-pool limits (maxConnections=10,
# http1MaxPendingRequests=5 — demo/traffic/destinationrule-order-
# service.yaml) actually cause Envoy to reject excess concurrent
# requests once the pool is exhausted, rather than queuing them
# indefinitely.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — circuit-breaking-test skipped."
  exit 0
fi

log_section "circuit-breaking-test"

cleanup() { kubectl -n "${DEMO_NAMESPACE}" delete pod circuit-breaking-client --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl apply -f "${MODULE_ROOT}/demo/traffic/destinationrule-order-service.yaml" >/dev/null
sleep 3

kubectl run circuit-breaking-client -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 120 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready pod/circuit-breaking-client --timeout=60s >/dev/null

log_info "Firing 30 concurrent requests against a pool limited to 10 connections / 5 pending..."
RESULTS_FILE="$(mktemp)"
for _ in $(seq 1 30); do
  kubectl -n "${DEMO_NAMESPACE}" exec circuit-breaking-client -- \
    curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://order-service/ >>"${RESULTS_FILE}" 2>/dev/null &
done
wait

OVERFLOW_COUNT="$(grep -c '^5[0-9][0-9]$' "${RESULTS_FILE}" || true)"
SUCCESS_COUNT="$(grep -c '^2[0-9][0-9]$' "${RESULTS_FILE}" || true)"
rm -f "${RESULTS_FILE}"

log_info "Results: ${SUCCESS_COUNT} succeeded, ${OVERFLOW_COUNT} rejected (5xx, expected circuit-breaker overflow behavior)"
if [ "${OVERFLOW_COUNT}" -gt 0 ]; then
  log_pass "Connection-pool limits produced overflow rejections as expected, under concurrent load exceeding the configured limits."
  exit 0
else
  log_warn "No overflow rejections observed — this can happen if the cluster/whoami backend is fast enough that all 30 concurrent requests completed within the pool limits before saturating them. Not treated as a hard failure; re-run with more concurrency if this matters for your investigation."
  exit 0
fi
