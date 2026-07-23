#!/usr/bin/env bash
# Summarizes PolicyReport/ClusterPolicyReport results across the cluster:
# failed policies, failed rules, affected resources, and messages. Uses
# jq if available for a clean summary; falls back to raw kubectl output.
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

log_section "PolicyReport summary"
kubectl get policyreports -A 2>/dev/null || log_info "No namespaced PolicyReports found yet."

log_section "ClusterPolicyReport summary"
kubectl get clusterpolicyreports 2>/dev/null || log_info "No ClusterPolicyReports found yet."

if command -v jq >/dev/null 2>&1; then
  log_section "Failed rules (all namespaces, jq summary)"
  kubectl get policyreports -A -o json 2>/dev/null \
    | jq -r '
        .items[]?
        | .metadata.namespace as $ns
        | (.results // [])[]?
        | select(.result == "fail" or .result == "warn" or .result == "error")
        | "\($ns)\t\(.policy)\t\(.rule)\t\(.result)\t\(.resources[0].name // "n/a")\t\(.message // "")"
      ' 2>/dev/null \
    | column -t -s "$(printf '\t')" \
    || log_info "No failed/warn/error results found, or jq parsing produced no rows."
else
  log_warn "jq is not installed — showing raw PolicyReport results instead of a summarized table."
  kubectl get policyreports -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.summary}{"\n"}{end}' 2>/dev/null || true
fi

log_section "Recent events in ${DEMO_NAMESPACE} (sorted)"
kubectl get events -n "${DEMO_NAMESPACE}" --sort-by=.metadata.creationTimestamp 2>/dev/null || log_info "Namespace ${DEMO_NAMESPACE} not found yet — run 'make deploy-demo' first."
