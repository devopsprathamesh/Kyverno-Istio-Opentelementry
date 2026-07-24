#!/usr/bin/env bash
# Quick, read-only status glance. Faster and less exhaustive than
# validate-installation.sh — a snapshot, not a pass/fail gate.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! command -v kubectl >/dev/null 2>&1 || ! kube_reachable; then
  log_info "No reachable cluster (or kubectl not installed) — nothing to show. Run 'make verify-cluster' for the specific reason."
  exit 0
fi

log_section "OpenTelemetry Operator + Collector (${OPENTELEMETRY_NAMESPACE})"
kubectl -n "${OPENTELEMETRY_NAMESPACE}" get pods -o wide 2>/dev/null || log_info "Namespace ${OPENTELEMETRY_NAMESPACE} not found."

log_section "Prometheus / Grafana / Jaeger / Loki (${OBSERVABILITY_NAMESPACE})"
kubectl -n "${OBSERVABILITY_NAMESPACE}" get pods -o wide 2>/dev/null || log_info "Namespace ${OBSERVABILITY_NAMESPACE} not found."

log_section "Demo application (${OTEL_DEMO_NAMESPACE})"
kubectl -n "${OTEL_DEMO_NAMESPACE}" get pods -o wide 2>/dev/null || log_info "Namespace ${OTEL_DEMO_NAMESPACE} not found."

log_section "Helm releases"
helm list -n "${OBSERVABILITY_NAMESPACE}" 2>/dev/null || true
helm list -n "${OPENTELEMETRY_NAMESPACE}" 2>/dev/null || true

log_section "Collector proxy status (if a port-forward is already active)"
log_info "Run 'make port-forward-*' targets, then 'make collector-status' to inspect internal metrics."
