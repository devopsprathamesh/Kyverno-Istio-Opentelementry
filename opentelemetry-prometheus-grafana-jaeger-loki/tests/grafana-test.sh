#!/usr/bin/env bash
# Runtime test: Grafana health, datasource health, dashboard provisioning.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=../scripts/lib/observability.sh
source "${MODULE_ROOT}/scripts/lib/observability.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — grafana-test skipped."
  exit 0
fi

FAIL=0
pass() { log_pass "$1"; }
fail() { log_fail "$1"; FAIL=1; }
log_section "grafana-test"

kubectl -n "${OBSERVABILITY_NAMESPACE}" port-forward "svc/${GRAFANA_SERVICE}" 13000:"${GRAFANA_PORT}" >/dev/null 2>&1 &
PF_PID=$!
cleanup() { kill "${PF_PID}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
sleep 3

if grafana_healthy 13000; then pass "Health endpoint OK"; else fail "Health endpoint not OK"; fi

if [ -f "${GENERATED_DIR}/grafana-admin-password" ]; then
  ADMIN_PASS="$(cat "${GENERATED_DIR}/grafana-admin-password")"
  for ds in prometheus jaeger loki; do
    if grafana_datasource_healthy 13000 "${ds}" "${GRAFANA_LAB_DEFAULT_USER}" "${ADMIN_PASS}"; then
      pass "Datasource '${ds}' healthy"
    else
      fail "Datasource '${ds}' not healthy"
    fi
  done
  DASHBOARD_COUNT="$(curl -fsS -u "${GRAFANA_LAB_DEFAULT_USER}:${ADMIN_PASS}" "http://127.0.0.1:13000/api/search?type=dash-db" 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
  if [ "${DASHBOARD_COUNT}" -ge 5 ]; then pass "At least 5 dashboards provisioned (found ${DASHBOARD_COUNT})"; else fail "Expected >= 5 dashboards, found ${DASHBOARD_COUNT}"; fi
else
  fail "No generated admin password found at ${GENERATED_DIR}/grafana-admin-password — run install-grafana.sh first."
fi

echo
if [ "${FAIL}" -gt 0 ]; then log_fail "grafana-test: ${FAIL} check(s) failed."; exit 1; fi
log_pass "grafana-test: all checks passed."
