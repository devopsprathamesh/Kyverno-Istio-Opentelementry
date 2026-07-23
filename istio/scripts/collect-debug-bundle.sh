#!/usr/bin/env bash
# Collects a sanitized troubleshooting bundle into
# .generated/debug-bundles/<timestamp>/ (git-ignored). Never collects
# Kubernetes Secret contents, redacts anything that looks like a token,
# and compresses the result only if a compression tool is available.
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

ensure_generated_dir
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
BUNDLE_DIR="${GENERATED_DIR}/debug-bundles/${TIMESTAMP}"
mkdir -p "${BUNDLE_DIR}"

log_section "Collecting debug bundle -> ${BUNDLE_DIR}"

redact() {
  # Strips anything that looks like a bearer token, JWT, or long
  # hex/base64 secret-shaped string from stdin.
  sed -E 's/(Bearer|Authorization: )[A-Za-z0-9._-]+/\1[REDACTED]/g; s/[A-Za-z0-9_-]{40,}/[REDACTED-LONG-TOKEN]/g'
}

{
  echo "Collected: $(date -Iseconds)"
  kubectl config current-context
} 2>&1 | redact >"${BUNDLE_DIR}/context.txt"

kubectl get nodes -o wide >"${BUNDLE_DIR}/nodes.txt" 2>&1 || true
kubectl -n "${ISTIO_SYSTEM_NAMESPACE}" get pods,svc,endpoints -o wide >"${BUNDLE_DIR}/istio-system-resources.txt" 2>&1 || true
kubectl -n "${ISTIO_INGRESS_NAMESPACE}" get pods,svc,endpoints -o wide >"${BUNDLE_DIR}/istio-ingress-resources.txt" 2>&1 || true
kubectl get crd | grep -i istio >"${BUNDLE_DIR}/istio-crds.txt" 2>&1 || true
helm list -A 2>&1 | redact >"${BUNDLE_DIR}/helm-releases.txt" || true

kubectl -n "${ISTIO_SYSTEM_NAMESPACE}" logs -l app=istiod --tail=500 --all-containers 2>&1 | redact >"${BUNDLE_DIR}/istiod-logs.txt" || true
kubectl -n "${ISTIO_SYSTEM_NAMESPACE}" logs -l k8s-app=istio-cni-node --tail=500 --all-containers 2>&1 | redact >"${BUNDLE_DIR}/istio-cni-logs.txt" || true
kubectl -n "${ISTIO_INGRESS_NAMESPACE}" logs -l app=istio-ingress --tail=500 --all-containers 2>&1 | redact >"${BUNDLE_DIR}/istio-ingress-logs.txt" || true

if command -v istioctl >/dev/null 2>&1; then
  istioctl analyze --all-namespaces >"${BUNDLE_DIR}/istioctl-analyze.txt" 2>&1 || true
  istioctl proxy-status >"${BUNDLE_DIR}/istioctl-proxy-status.txt" 2>&1 || true
fi

kubectl get events -A --sort-by=.metadata.creationTimestamp >"${BUNDLE_DIR}/events.txt" 2>&1 || true

if kubectl -n kube-system exec daemonset/cilium -- cilium status >"${BUNDLE_DIR}/cilium-status.txt" 2>&1; then
  log_pass "Collected Cilium status."
else
  log_warn "Could not collect Cilium status (daemonset/cilium exec failed) — non-fatal."
fi
if command -v hubble >/dev/null 2>&1; then
  hubble observe --namespace "${DEMO_NAMESPACE}" --last 50 >"${BUNDLE_DIR}/hubble-flow-sample.txt" 2>&1 || true
fi

# Explicitly never collect Secret contents — document that this bundle
# does not include them, rather than silently omitting an expected file.
echo "Kubernetes Secret contents are intentionally NOT collected by this script." >"${BUNDLE_DIR}/NOTE-secrets-excluded.txt"

if command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
  (cd "${GENERATED_DIR}/debug-bundles" && tar -czf "${TIMESTAMP}.tar.gz" "${TIMESTAMP}" && rm -rf "${TIMESTAMP}")
  log_pass "Debug bundle compressed: ${GENERATED_DIR}/debug-bundles/${TIMESTAMP}.tar.gz"
else
  log_info "Compression tools not available — bundle left uncompressed at ${BUNDLE_DIR}"
fi
