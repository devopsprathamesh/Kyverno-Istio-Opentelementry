#!/usr/bin/env bash
# Removes the Helm releases (and, for the Collector, the raw manifests
# clean.sh doesn't already cover) for one or all tools. CRDs (Operator's
# OpenTelemetryCollector/Instrumentation, Prometheus Operator's
# ServiceMonitor/PodMonitor/PrometheusRule/Alertmanager) are kept by
# default — REMOVE_CRDS=true also removes them (cluster-wide, not just
# this lab's own resources of that kind). Never touches Cilium,
# kube-proxy, or the cluster itself.
#
# Usage: uninstall-all.sh [prometheus|grafana|jaeger|loki|operator|collector|all]
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm
if ! kube_reachable; then
  log_info "No reachable cluster — nothing to uninstall."
  exit 0
fi

SCOPE="${1:-all}"
REMOVE_CRDS="${REMOVE_CRDS:-false}"

uninstall_grafana() { helm uninstall grafana -n "${OBSERVABILITY_NAMESPACE}" --ignore-not-found 2>/dev/null || true; log_pass "Grafana Helm release removed."; }
uninstall_loki() { helm uninstall loki -n "${OBSERVABILITY_NAMESPACE}" --ignore-not-found 2>/dev/null || true; log_pass "Loki Helm release removed."; }
uninstall_jaeger() { helm uninstall jaeger -n "${OBSERVABILITY_NAMESPACE}" --ignore-not-found 2>/dev/null || true; log_pass "Jaeger Helm release removed."; }
uninstall_prometheus() {
  helm uninstall kube-prometheus-stack -n "${OBSERVABILITY_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  log_pass "kube-prometheus-stack Helm release removed."
  if [ "${REMOVE_CRDS}" = "true" ]; then
    log_warn "REMOVE_CRDS=true: deleting Prometheus Operator CRDs cluster-wide (ServiceMonitor/PodMonitor/PrometheusRule/Alertmanager/etc. — affects ANY release of these CRDs on this cluster, not just this module's)."
    kubectl get crd -o name 2>/dev/null | grep 'monitoring.coreos.com' | xargs -r kubectl delete
  fi
}
uninstall_collector() {
  "${MODULE_ROOT}/scripts/clean.sh" collector
  kubectl -n "${OPENTELEMETRY_NAMESPACE}" delete serviceaccount otel-collector-agent otel-collector-gateway --ignore-not-found >/dev/null
  kubectl delete clusterrole otel-collector-agent otel-collector-gateway --ignore-not-found >/dev/null
  kubectl delete clusterrolebinding otel-collector-agent otel-collector-gateway --ignore-not-found >/dev/null
  log_pass "Collector RBAC removed."
}
uninstall_operator() {
  helm uninstall opentelemetry-operator -n "${OPENTELEMETRY_NAMESPACE}" --ignore-not-found 2>/dev/null || true
  log_pass "OpenTelemetry Operator Helm release removed."
  if [ "${REMOVE_CRDS}" = "true" ]; then
    log_warn "REMOVE_CRDS=true: deleting opentelemetry.io CRDs cluster-wide."
    kubectl get crd -o name 2>/dev/null | grep 'opentelemetry.io' | xargs -r kubectl delete
  fi
}

case "${SCOPE}" in
  grafana) uninstall_grafana ;;
  loki) uninstall_loki ;;
  jaeger) uninstall_jaeger ;;
  prometheus) uninstall_prometheus ;;
  collector) uninstall_collector ;;
  operator) uninstall_operator ;;
  all)
    echo "[WARN] DESTRUCTIVE: removing Grafana, Loki, Jaeger, Prometheus stack, Collector, and Operator from this cluster."
    echo "[WARN] CRDs are kept by default — set REMOVE_CRDS=true to also delete them (affects any other release of the same CRDs cluster-wide, not just this module's)."
    uninstall_grafana
    uninstall_loki
    uninstall_jaeger
    uninstall_collector
    uninstall_prometheus
    uninstall_operator
    ;;
  *) log_fatal "Unknown scope '${SCOPE}'. Valid: prometheus|grafana|jaeger|loki|operator|collector|all" ;;
esac

log_pass "uninstall-all (scope=${SCOPE}) complete. kube-system, Cilium, kube-proxy, and every other module are untouched."
