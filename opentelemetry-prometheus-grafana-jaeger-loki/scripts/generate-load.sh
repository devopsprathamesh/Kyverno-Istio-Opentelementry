#!/usr/bin/env bash
# Runs the load-generator's one-shot mode against the frontend Service
# from a temporary pod (reuses the deployed load-generator image rather
# than a bespoke curl loop, so load characteristics match what
# combined-observability-lab/scenarios/ describes). Usage:
#   generate-load.sh [REQUESTS] [CONCURRENCY] [DURATION_SECONDS]
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

REQUESTS="${1:-${LOAD_DEFAULT_REQUESTS}}"
CONCURRENCY="${2:-${LOAD_DEFAULT_CONCURRENCY}}"
DURATION="${3:-${LOAD_DEFAULT_DURATION_SECONDS}}"

log_section "Generating load: ${REQUESTS} requests, concurrency ${CONCURRENCY}, up to ${DURATION}s"

JOB_NAME="load-gen-$(date +%s)"
cleanup() { kubectl -n "${OTEL_DEMO_NAMESPACE}" delete job "${JOB_NAME}" --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl -n "${OTEL_DEMO_NAMESPACE}" create job "${JOB_NAME}" \
  --image="${DEMO_LOAD_GENERATOR_IMAGE}:${DEMO_LOAD_GENERATOR_IMAGE_TAG}" \
  -- python3 loadgen.py --requests "${REQUESTS}" --concurrency "${CONCURRENCY}" --duration "${DURATION}" \
     --target "http://frontend.${OTEL_DEMO_NAMESPACE}.svc.cluster.local:${DEMO_FRONTEND_PORT}" >/dev/null

kubectl -n "${OTEL_DEMO_NAMESPACE}" wait --for=condition=complete "job/${JOB_NAME}" --timeout="$((DURATION + 60))s" || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" logs "job/${JOB_NAME}" --tail=50 || true

log_pass "Load generation complete. Check Grafana/Prometheus/Jaeger/Loki for the resulting telemetry."
