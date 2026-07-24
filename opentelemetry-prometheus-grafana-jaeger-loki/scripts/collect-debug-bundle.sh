#!/usr/bin/env bash
# Collects a sanitized troubleshooting bundle into
# .generated/debug-bundles/<timestamp>/ (git-ignored). Never collects
# Kubernetes Secret contents, passwords, tokens, private keys, or full
# kubeconfig — redacts anything that looks like a bearer token/JWT/long
# secret-shaped string.
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
  sed -E 's/(Bearer|Authorization: )[A-Za-z0-9._-]+/\1[REDACTED]/g; s/[A-Za-z0-9_-]{40,}/[REDACTED-LONG-TOKEN]/g'
}

{
  echo "Collected: $(date -Iseconds)"
  kubectl config current-context
} 2>&1 | redact >"${BUNDLE_DIR}/context.txt"

kubectl get nodes -o wide >"${BUNDLE_DIR}/nodes.txt" 2>&1 || true

for ns in "${OBSERVABILITY_NAMESPACE}" "${OPENTELEMETRY_NAMESPACE}" "${OTEL_DEMO_NAMESPACE}"; do
  kubectl -n "${ns}" get pods,svc,endpoints,deployments,daemonsets,statefulsets -o wide >"${BUNDLE_DIR}/${ns}-resources.txt" 2>&1 || true
  kubectl -n "${ns}" get events --sort-by=.metadata.creationTimestamp >"${BUNDLE_DIR}/${ns}-events.txt" 2>&1 || true
done

kubectl get crd 2>/dev/null | grep -iE 'opentelemetry|monitoring.coreos' >"${BUNDLE_DIR}/observability-crds.txt" 2>&1 || true
helm list -n "${OBSERVABILITY_NAMESPACE}" -n "${OPENTELEMETRY_NAMESPACE}" 2>&1 | redact >"${BUNDLE_DIR}/helm-releases.txt" || true

kubectl -n "${OPENTELEMETRY_NAMESPACE}" logs -l app=otel-collector-agent --tail=500 --all-containers 2>&1 | redact >"${BUNDLE_DIR}/collector-agent-logs.txt" || true
kubectl -n "${OPENTELEMETRY_NAMESPACE}" logs -l app=otel-collector-gateway --tail=500 --all-containers 2>&1 | redact >"${BUNDLE_DIR}/collector-gateway-logs.txt" || true
kubectl -n "${OPENTELEMETRY_NAMESPACE}" logs -l app.kubernetes.io/name=opentelemetry-operator --tail=500 --all-containers 2>&1 | redact >"${BUNDLE_DIR}/operator-logs.txt" || true
kubectl -n "${OPENTELEMETRY_NAMESPACE}" get configmap otel-collector-agent-config otel-collector-gateway-config -o yaml 2>&1 | redact >"${BUNDLE_DIR}/collector-configs.txt" || true

kubectl -n "${OBSERVABILITY_NAMESPACE}" get prometheus,servicemonitor,podmonitor,prometheusrule -o wide >"${BUNDLE_DIR}/prometheus-objects.txt" 2>&1 || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" logs -l app=frontend --tail=200 2>&1 | redact >"${BUNDLE_DIR}/frontend-logs.txt" || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" logs -l app=order-service --tail=200 2>&1 | redact >"${BUNDLE_DIR}/order-service-logs.txt" || true
kubectl -n "${OTEL_DEMO_NAMESPACE}" logs -l app=payment-service --tail=200 2>&1 | redact >"${BUNDLE_DIR}/payment-service-logs.txt" || true

if kubectl -n kube-system exec daemonset/cilium -- cilium status >"${BUNDLE_DIR}/cilium-status.txt" 2>&1; then
  log_pass "Collected Cilium status."
else
  log_warn "Could not collect Cilium status (daemonset/cilium exec failed) — non-fatal."
fi
if command -v hubble >/dev/null 2>&1; then
  hubble observe --namespace "${OTEL_DEMO_NAMESPACE}" --last 50 >"${BUNDLE_DIR}/hubble-flow-sample.txt" 2>&1 || true
fi

echo "Kubernetes Secret contents, passwords, tokens, private keys, and full kubeconfig are intentionally NOT collected by this script." >"${BUNDLE_DIR}/NOTE-secrets-excluded.txt"

if command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
  (cd "${GENERATED_DIR}/debug-bundles" && tar -czf "${TIMESTAMP}.tar.gz" "${TIMESTAMP}" && rm -rf "${TIMESTAMP}")
  log_pass "Debug bundle compressed: ${GENERATED_DIR}/debug-bundles/${TIMESTAMP}.tar.gz"
else
  log_info "Compression tools not available — bundle left uncompressed at ${BUNDLE_DIR}"
fi
