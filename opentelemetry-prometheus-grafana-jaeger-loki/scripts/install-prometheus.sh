#!/usr/bin/env bash
# Installs the kube-prometheus-stack chart (Prometheus + Prometheus
# Operator + Alertmanager + kube-state-metrics + node-exporter). See
# docs/DECISIONS.md ADR-025 for why the full stack chart is used
# instead of bare Prometheus.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm

PROFILE="$(profile_arg)"
VALUES_FILE="${MODULE_ROOT}/install/prometheus/values-${PROFILE}.yaml"
[ -f "${VALUES_FILE}" ] || log_fatal "Values file not found: ${VALUES_FILE}"

log_section "Installing kube-prometheus-stack ${KUBE_PROMETHEUS_STACK_CHART_VERSION}, profile=${PROFILE}"

kubectl apply -f "${MODULE_ROOT}/install/namespaces/"

helm repo add "${PROMETHEUS_COMMUNITY_HELM_REPO_NAME}" "${PROMETHEUS_COMMUNITY_HELM_REPO}" >/dev/null 2>&1 || true
helm repo update "${PROMETHEUS_COMMUNITY_HELM_REPO_NAME}" >/dev/null

helm upgrade --install kube-prometheus-stack "${PROMETHEUS_COMMUNITY_HELM_REPO_NAME}/kube-prometheus-stack" \
  --version "${KUBE_PROMETHEUS_STACK_CHART_VERSION}" \
  --namespace "${OBSERVABILITY_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait --timeout "${HELM_TIMEOUT}"

log_pass "kube-prometheus-stack applied (Prometheus, Prometheus Operator, Alertmanager, kube-state-metrics, node-exporter)."

log_info "Applying recording rules, alerting rules, and ServiceMonitors/PodMonitors..."
kubectl apply -f "${MODULE_ROOT}/prometheus/recording-rules/" 2>/dev/null || true
kubectl apply -f "${MODULE_ROOT}/prometheus/alerts/" 2>/dev/null || true
log_pass "Prometheus rule objects applied (ServiceMonitors/PodMonitors are applied by install-collector.sh once the Collector Gateway Service exists)."

log_pass "Prometheus installation complete. Run 'make validate-prometheus' next."
