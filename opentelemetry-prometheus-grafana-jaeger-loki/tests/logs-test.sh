#!/usr/bin/env bash
# Runtime test: end-to-end log delivery via the filelog path — demo app
# container stdout -> node log file -> Agent filelog receiver -> Gateway
# -> Loki. Also checks for the two specific risks
# docs/06-logs.md documents: duplication and missing Kubernetes metadata.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — logs-test skipped."
  exit 0
fi
if ! namespace_exists "${OTEL_DEMO_NAMESPACE}"; then
  log_info "Demo namespace not found — run 'make deploy-demo' first. logs-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "logs-test"

kubectl -n "${OTEL_DEMO_NAMESPACE}" run logs-test-client --image=curlimages/curl:8.10.1 --restart=Never \
  --labels="${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --command -- sleep 60 >/dev/null 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" wait --for=condition=Ready pod/logs-test-client --timeout=60s >/dev/null 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" exec logs-test-client -- curl -fsS -X POST "http://frontend.${OTEL_DEMO_NAMESPACE}.svc.cluster.local:${DEMO_FRONTEND_PORT}/" >/dev/null 2>&1 || true

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${LOKI_SERVICE}" 13100:"${LOKI_PORT}" >/dev/null 2>&1 &
PF_PID=$!
cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
  kubectl -n "${OTEL_DEMO_NAMESPACE}" delete pod logs-test-client --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 5

if loki_query_has_result 13100 '{k8s_namespace_name="otel-demo"}'; then
  pass "Demo app logs are reaching Loki"
else
  fail "No demo app logs found in Loki — check Collector Agent filelog receiver (permissions, path) and the Gateway's otlphttp/loki exporter"
fi

if loki_query_has_result 13100 '{k8s_namespace_name="otel-demo", service_name="order-service"}'; then
  pass "Kubernetes namespace/service metadata present on log streams (k8sattributes processor working)"
else
  fail "Logs found but not correctly labeled with k8s_namespace_name/service_name — check the k8sattributes processor in collector/agent/configmap.yaml"
fi

BODY="$(loki_query_range 13100 '{k8s_namespace_name="otel-demo", service_name="order-service"}')"
COUNT="$(printf '%s' "${BODY}" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    streams=d.get("data",{}).get("result",[])
    print(sum(len(s.get("values",[])) for s in streams))
except Exception:
    print(0)' 2>/dev/null || echo 0)"
log_info "order-service log sample count in the query window: ${COUNT} (a spot-check only — this does not prove absence of duplication over the full retention window, see docs/21-troubleshooting.md 'Duplicate logs')"

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "logs-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "logs-test: all checks passed."
