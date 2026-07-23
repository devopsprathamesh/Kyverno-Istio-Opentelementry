#!/usr/bin/env bash
# Quick, read-only status glance: Kyverno controllers, webhook presence,
# policy counts, demo namespace state. Faster and less exhaustive than
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

log_section "Kyverno controllers"
kubectl -n "${KYVERNO_NAMESPACE}" get deployments -o wide 2>/dev/null || log_info "Namespace ${KYVERNO_NAMESPACE} not found — Kyverno is not installed."

log_section "Webhooks"
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations 2>/dev/null | grep -i kyverno || log_info "No Kyverno webhooks found."

log_section "Policies"
kubectl get clusterpolicies,policies -A 2>/dev/null || log_info "No policies found."

log_section "Demo namespace"
kubectl get all -n "${DEMO_NAMESPACE}" 2>/dev/null || log_info "Namespace ${DEMO_NAMESPACE} not found — run 'make deploy-demo'."

log_section "Policy reports (counts only — use 'make reports' for detail)"
kubectl get policyreports -A --no-headers 2>/dev/null | wc -l | xargs -I{} log_info "{} PolicyReport object(s) across all namespaces."
