#!/usr/bin/env bash
# Generates a bounded, controlled burst of HTTP requests against a
# target (default: the frontend Service inside the mesh, via a
# temporary sleep+curl client pod) and reports the response
# distribution — used by the canary-routing lab (statistical
# tolerance validation) and generally for exercising traffic-management
# rules. Never targets anything outside DEMO_NAMESPACE/EXTERNAL_NAMESPACE.
#
# Usage: generate-traffic.sh [TARGET_URL] [REQUEST_COUNT] [CONCURRENCY]
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

TARGET_URL="${1:-http://frontend.${DEMO_NAMESPACE}.svc.cluster.local}"
REQUEST_COUNT="${2:-${TRAFFIC_DEFAULT_REQUESTS}}"
CONCURRENCY="${3:-${TRAFFIC_DEFAULT_CONCURRENCY}}"

log_section "Generating traffic: ${REQUEST_COUNT} requests (concurrency ${CONCURRENCY}) -> ${TARGET_URL}"

CLIENT_POD="traffic-gen-$(date +%s)"
cleanup() { kubectl -n "${DEMO_NAMESPACE}" delete pod "${CLIENT_POD}" --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl run "${CLIENT_POD}" -n "${DEMO_NAMESPACE}" --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE},app=traffic-gen" \
  --command -- sleep 300 >/dev/null
kubectl -n "${DEMO_NAMESPACE}" wait --for=condition=Ready "pod/${CLIENT_POD}" --timeout=60s >/dev/null

RESULTS_FILE="$(mktemp)"
for ((i = 1; i <= REQUEST_COUNT; i++)); do
  kubectl -n "${DEMO_NAMESPACE}" exec "${CLIENT_POD}" -- \
    curl -s -o /dev/null -w '%{http_code} %{hostname}\n' --max-time 5 "${TARGET_URL}" 2>/dev/null >>"${RESULTS_FILE}" || true
  if (( i % CONCURRENCY == 0 )); then wait; fi
done

log_section "Response summary"
TOTAL="$(wc -l <"${RESULTS_FILE}")"
log_info "Total responses recorded: ${TOTAL} / ${REQUEST_COUNT} requested"
awk '{print $1}' "${RESULTS_FILE}" | sort | uniq -c | sort -rn | while read -r count code; do
  log_info "  HTTP ${code}: ${count} (${count}00/${TOTAL} approx.)"
done
rm -f "${RESULTS_FILE}"
