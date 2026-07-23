#!/usr/bin/env bash
# Installs Istio (sidecar mode + Istio CNI plugin) via the official Helm
# charts, pinned per config/versions.env, using the values files
# matching LAB_PROFILE. Idempotent via `helm upgrade --install`.
# Requires verify-cluster.sh to have already passed (the Makefile
# enforces this ordering).
#
# Install order (per official Istio CNI-chained-install guidance):
#   base (CRDs) -> Cilium CNI-chaining hard-check -> istiod -> istio-cni
#   -> gateway (ingress)
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"
# shellcheck source=./lib/istio.sh
source "${MODULE_ROOT}/scripts/lib/istio.sh"

require_cmd kubectl
require_cmd helm

PROFILE="$(profile_arg)"
ISTIOD_VALUES="${MODULE_ROOT}/install/istiod-values-${PROFILE}.yaml"
GATEWAY_VALUES="${MODULE_ROOT}/install/ingress-gateway-values-${PROFILE}.yaml"
[ -f "${ISTIOD_VALUES}" ] || log_fatal "Values file not found: ${ISTIOD_VALUES}"
[ -f "${GATEWAY_VALUES}" ] || log_fatal "Values file not found: ${GATEWAY_VALUES}"

log_section "Installing Istio ${ISTIO_VERSION}, profile=${PROFILE}, revision=${ISTIO_REVISION}"

kubectl apply -f "${MODULE_ROOT}/install/namespace.yaml"
log_pass "Namespaces ${ISTIO_SYSTEM_NAMESPACE}/${ISTIO_INGRESS_NAMESPACE} ensured."

helm repo add "${ISTIO_HELM_REPO_NAME}" "${ISTIO_HELM_REPO}" >/dev/null 2>&1 || true
helm repo update "${ISTIO_HELM_REPO_NAME}" >/dev/null

log_info "Step 1/4: base (CRDs + cluster resources)"
helm upgrade --install istio-base "${ISTIO_HELM_REPO_NAME}/base" \
  --version "${ISTIO_CHART_BASE_VERSION}" \
  --namespace "${ISTIO_SYSTEM_NAMESPACE}" \
  --values "${MODULE_ROOT}/install/base-values.yaml" \
  --wait --timeout "${INSTALL_WAIT_TIMEOUT_SECONDS}s"
log_pass "istio-base applied."

log_info "Applying Gateway API CRDs (${GATEWAY_API_VERSION}) if not already present..."
ensure_generated_dir
if ! crd_exists gateways.gateway.networking.k8s.io; then
  kubectl apply -f "${GATEWAY_API_CRDS_URL}"
  echo "installed-by-this-lab" >"${GENERATED_DIR}/gateway-api-crds-owned.marker"
  log_pass "Gateway API ${GATEWAY_API_VERSION} CRDs applied. Ownership marker written so 'make uninstall' knows it's safe to remove them later."
else
  log_info "Gateway API CRDs already present, skipping (this module never assumes ownership of CRDs it didn't install — see uninstall.sh)."
fi

log_section "Cilium CNI-chaining compatibility (hard check before istio-cni)"
if command -v helm >/dev/null 2>&1 && cilium_cni_chaining_ready; then
  log_pass "Cilium CNI-chaining values confirmed."
else
  print_cilium_cni_chaining_remediation
  log_fatal "Refusing to install istio-cni against a Cilium release that isn't confirmed CNI-chaining-compatible. Apply the remediation above, then re-run 'make install'."
fi

log_info "Step 2/4: istiod (control plane)"
helm upgrade --install istiod "${ISTIO_HELM_REPO_NAME}/istiod" \
  --version "${ISTIO_CHART_ISTIOD_VERSION}" \
  --namespace "${ISTIO_SYSTEM_NAMESPACE}" \
  --values "${ISTIOD_VALUES}" \
  --set revision="${ISTIO_REVISION}" \
  --wait --timeout "${INSTALL_WAIT_TIMEOUT_SECONDS}s"
log_pass "istiod applied (revision=${ISTIO_REVISION})."

log_info "Step 3/4: istio-cni"
helm upgrade --install istio-cni "${ISTIO_HELM_REPO_NAME}/cni" \
  --version "${ISTIO_CHART_CNI_VERSION}" \
  --namespace "${ISTIO_SYSTEM_NAMESPACE}" \
  --values "${MODULE_ROOT}/install/cni-values.yaml" \
  --set revision="${ISTIO_REVISION}" \
  --wait --timeout "${INSTALL_WAIT_TIMEOUT_SECONDS}s"
log_pass "istio-cni applied."

log_info "Step 4/4: gateway (ingress)"
kubectl create namespace "${ISTIO_INGRESS_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "${ISTIO_INGRESS_NAMESPACE}" istio.io/rev="${ISTIO_REVISION}" --overwrite >/dev/null
helm upgrade --install istio-ingress "${ISTIO_HELM_REPO_NAME}/gateway" \
  --version "${ISTIO_CHART_GATEWAY_VERSION}" \
  --namespace "${ISTIO_INGRESS_NAMESPACE}" \
  --values "${GATEWAY_VALUES}" \
  --wait --timeout "${INSTALL_WAIT_TIMEOUT_SECONDS}s"
log_pass "istio-ingress gateway applied."

log_pass "Istio installation complete. Run 'make validate-installation' next."
