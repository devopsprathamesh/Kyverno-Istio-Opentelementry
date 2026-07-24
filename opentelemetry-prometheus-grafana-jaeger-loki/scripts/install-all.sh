#!/usr/bin/env bash
# Orchestrates a full install in dependency order: namespaces -> Operator
# (CRDs + webhook) -> Prometheus -> Jaeger -> Loki -> Collector (agent +
# gateway, needs the backends' Services to exist) -> Grafana (needs the
# other three's Services up for datasource health checks). Idempotent —
# safe to re-run.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

PROFILE="$(profile_arg)"
log_section "Installing the full observability stack, profile=${PROFILE}"

export LAB_PROFILE="${PROFILE}"
"${MODULE_ROOT}/scripts/install-operator.sh"
"${MODULE_ROOT}/scripts/install-prometheus.sh"
"${MODULE_ROOT}/scripts/install-jaeger.sh"
"${MODULE_ROOT}/scripts/install-loki.sh"
"${MODULE_ROOT}/scripts/install-collector.sh"
"${MODULE_ROOT}/scripts/install-grafana.sh"

log_pass "Full observability stack installed. Run 'make validate-installation' next, then 'make build-demo-images && make deploy-demo'."
