#!/usr/bin/env bash
# Installs Jaeger v2 via the official jaegertracing/helm-charts chart —
# NOT the Jaeger Operator, which is deprecated upstream ("only works
# with retired Jaeger v1"). Jaeger v2 is itself an OpenTelemetry
# Collector distribution with a native, stable OTLP receiver — no
# separate Collector is required in front of it. See
# docs/DECISIONS.md ADR-027.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm

PROFILE="$(profile_arg)"
VALUES_FILE="${MODULE_ROOT}/install/jaeger/values-${PROFILE}.yaml"
[ -f "${VALUES_FILE}" ] || log_fatal "Values file not found: ${VALUES_FILE}"

log_section "Installing Jaeger ${JAEGER_APP_VERSION}, profile=${PROFILE}"

kubectl apply -f "${MODULE_ROOT}/install/namespaces/"

helm repo add "${JAEGER_HELM_REPO_NAME}" "${JAEGER_HELM_REPO}" >/dev/null 2>&1 || true
helm repo update "${JAEGER_HELM_REPO_NAME}" >/dev/null

helm upgrade --install jaeger "${JAEGER_HELM_REPO_NAME}/jaeger" \
  --version "${JAEGER_HELM_CHART_VERSION}" \
  --namespace "${OBSERVABILITY_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --set image.tag="${JAEGER_APP_VERSION}" \
  --wait --timeout "${HELM_TIMEOUT}"

log_pass "Jaeger applied. OTLP receiver reachable in-cluster at ${JAEGER_COLLECTOR_OTLP_GRPC_SERVICE}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${JAEGER_OTLP_GRPC_PORT} (gRPC) / :${JAEGER_OTLP_HTTP_PORT} (HTTP)."
if [ "${PROFILE}" = "minimum" ]; then
  log_warn "Profile 'minimum' uses Jaeger's in-memory storage — traces do not survive a pod restart. See docs/13-jaeger-architecture.md."
fi

log_pass "Jaeger installation complete. Run 'make validate-jaeger' next."
