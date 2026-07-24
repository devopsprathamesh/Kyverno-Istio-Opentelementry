#!/usr/bin/env bash
# Installs Loki (Monolithic deployment mode — the current chart
# terminology; SimpleScalable is deprecated, slated for removal in
# Loki 4.0) via the grafana-community Helm repo (the legacy
# grafana.github.io/helm-charts index is stale for this chart — see
# docs/VERSIONS.md Phase 5 addendum). Loki ingests logs natively via
# OTLP at POST /otlp/v1/logs — no Promtail, no Collector `loki`
# exporter (removed from Collector Contrib, not merely deprecated).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm

PROFILE="$(profile_arg)"
VALUES_FILE="${MODULE_ROOT}/install/loki/values-${PROFILE}.yaml"
[ -f "${VALUES_FILE}" ] || log_fatal "Values file not found: ${VALUES_FILE}"

log_section "Installing Loki (chart ${LOKI_HELM_CHART_VERSION}, app ${LOKI_APP_VERSION}), profile=${PROFILE}, mode=${LOKI_DEPLOYMENT_MODE}"

kubectl apply -f "${MODULE_ROOT}/install/namespaces/"

helm repo add "${GRAFANA_HELM_REPO_NAME}" "${GRAFANA_HELM_REPO}" >/dev/null 2>&1 || true
helm repo update "${GRAFANA_HELM_REPO_NAME}" >/dev/null

helm upgrade --install loki "${GRAFANA_HELM_REPO_NAME}/loki" \
  --version "${LOKI_HELM_CHART_VERSION}" \
  --namespace "${OBSERVABILITY_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait --timeout "${HELM_TIMEOUT}"

log_pass "Loki applied. Native OTLP ingest reachable in-cluster at http://${LOKI_SERVICE}.${OBSERVABILITY_NAMESPACE}.svc.cluster.local:${LOKI_PORT}/otlp (POST /otlp/v1/logs — the Collector's otlphttp exporter appends /v1/logs itself, endpoint must be set to the /otlp path only)."

log_pass "Loki installation complete. Run 'make validate-loki' next."
