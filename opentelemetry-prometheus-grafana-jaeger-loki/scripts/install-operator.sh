#!/usr/bin/env bash
# Installs the OpenTelemetry Operator via its official Helm chart. Uses
# Helm's built-in self-signed webhook certificate (autoGenerateCert) —
# cert-manager is NOT installed by this module, see
# install/cert-manager/README.md and docs/DECISIONS.md ADR-026.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm

log_section "Installing OpenTelemetry Operator ${OTEL_OPERATOR_IMAGE_VERSION}"

kubectl apply -f "${MODULE_ROOT}/install/namespaces/"
log_pass "Namespaces ensured."

helm repo add "${OTEL_HELM_REPO_NAME}" "${OTEL_HELM_REPO}" >/dev/null 2>&1 || true
helm repo update "${OTEL_HELM_REPO_NAME}" >/dev/null

helm upgrade --install opentelemetry-operator "${OTEL_HELM_REPO_NAME}/opentelemetry-operator" \
  --version "${OTEL_OPERATOR_HELM_CHART_VERSION}" \
  --namespace "${OPENTELEMETRY_NAMESPACE}" \
  --values "${MODULE_ROOT}/install/opentelemetry-operator/values.yaml" \
  --set manager.image.tag="${OTEL_OPERATOR_IMAGE_VERSION}" \
  --wait --timeout "${HELM_TIMEOUT}"

log_pass "OpenTelemetry Operator applied. Waiting for the webhook to be ready before any Instrumentation/OpenTelemetryCollector resource is applied..."
wait_for "opentelemetry-operator webhook Ready" "${POD_READY_TIMEOUT_SECONDS}" 5 -- \
  any_webhook_exists mutating opentelemetry-operator-mutation

log_pass "OpenTelemetry Operator installation complete. Run 'make validate-operator' next."
