#!/usr/bin/env bash
# Foreground port-forward to one of this module's UIs, localhost-bound
# only (never a public/host-bound port). Usage:
#   port-forward.sh <prometheus|grafana|jaeger|loki|demo> [LOCAL_PORT]
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

TARGET="${1:-}"
[ -n "${TARGET}" ] || log_fatal "Usage: $0 <prometheus|grafana|jaeger|loki|demo> [LOCAL_PORT]"

case "${TARGET}" in
  prometheus) NS="${OBSERVABILITY_NAMESPACE}"; SVC="${PROMETHEUS_SERVICE}"; REMOTE="${PROMETHEUS_PORT}"; DEFAULT_LOCAL=9090 ;;
  grafana) NS="${OBSERVABILITY_NAMESPACE}"; SVC="${GRAFANA_SERVICE}"; REMOTE="${GRAFANA_PORT}"; DEFAULT_LOCAL=3000 ;;
  jaeger) NS="${OBSERVABILITY_NAMESPACE}"; SVC="${JAEGER_QUERY_SERVICE}"; REMOTE="${JAEGER_QUERY_PORT}"; DEFAULT_LOCAL=16686 ;;
  loki) NS="${OBSERVABILITY_NAMESPACE}"; SVC="${LOKI_SERVICE}"; REMOTE="${LOKI_PORT}"; DEFAULT_LOCAL=3100 ;;
  demo) NS="${OTEL_DEMO_NAMESPACE}"; SVC="frontend"; REMOTE="${DEMO_FRONTEND_PORT}"; DEFAULT_LOCAL=8080 ;;
  *) log_fatal "Unknown target '${TARGET}'. Valid: prometheus|grafana|jaeger|loki|demo" ;;
esac

LOCAL_PORT="${2:-${DEFAULT_LOCAL}}"
log_info "Port-forwarding 127.0.0.1:${LOCAL_PORT} -> ${SVC}.${NS}.svc.cluster.local:${REMOTE} (Ctrl-C to stop)"
kubectl -n "${NS}" port-forward "svc/${SVC}" "127.0.0.1:${LOCAL_PORT}:${REMOTE}"
