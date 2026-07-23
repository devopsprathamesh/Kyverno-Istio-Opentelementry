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

log_section "Istio control plane"
kubectl -n "${ISTIO_SYSTEM_NAMESPACE}" get pods -o wide 2>/dev/null || log_info "Namespace ${ISTIO_SYSTEM_NAMESPACE} not found — Istio is not installed."

log_section "Istio ingress gateway"
kubectl -n "${ISTIO_INGRESS_NAMESPACE}" get pods,svc -o wide 2>/dev/null || log_info "Namespace ${ISTIO_INGRESS_NAMESPACE} not found."

log_section "Demo application"
kubectl -n "${DEMO_NAMESPACE}" get pods,svc,deploy -o wide 2>/dev/null || log_info "Namespace ${DEMO_NAMESPACE} not found — run 'make deploy-demo'."

log_section "Istio config objects in demo namespace"
kubectl -n "${DEMO_NAMESPACE}" get virtualservices,destinationrules,gateways,serviceentries,sidecars,peerauthentications,authorizationpolicies,requestauthentications 2>/dev/null || true

if command -v istioctl >/dev/null 2>&1; then
  log_section "istioctl proxy-status"
  istioctl proxy-status 2>/dev/null || log_info "istioctl proxy-status failed — control plane may not be ready."
fi
