#!/usr/bin/env bash
# Installs Kyverno via its official Helm chart, pinned per
# config/versions.env, using the values file matching LAB_PROFILE.
# Idempotent via `helm upgrade --install`. Requires verify-cluster.sh to
# have already passed (callers — the Makefile — enforce this ordering).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm

PROFILE="$(profile_arg)"
VALUES_FILE="${MODULE_ROOT}/install/values-${PROFILE}.yaml"
[ -f "${VALUES_FILE}" ] || log_fatal "Values file not found: ${VALUES_FILE}"

log_section "Installing Kyverno ${KYVERNO_CHART_VERSION} (app ${KYVERNO_APP_VERSION}), profile=${PROFILE}"

kubectl apply -f "${MODULE_ROOT}/install/namespace.yaml"
log_pass "Namespace '${KYVERNO_NAMESPACE}' ensured."

helm repo add "${KYVERNO_HELM_REPO_NAME}" "${KYVERNO_CHART_REPO}" >/dev/null 2>&1 || true
helm repo update "${KYVERNO_HELM_REPO_NAME}" >/dev/null

helm upgrade --install kyverno "${KYVERNO_HELM_REPO_NAME}/kyverno" \
  --version "${KYVERNO_CHART_VERSION}" \
  --namespace "${KYVERNO_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --wait --timeout "${INSTALL_WAIT_TIMEOUT_SECONDS}s"
log_pass "Helm release 'kyverno' applied (chart ${KYVERNO_CHART_VERSION})."

log_info "Waiting for CRDs..."
for crd in clusterpolicies.kyverno.io policies.kyverno.io policyexceptions.kyverno.io \
           cleanuppolicies.kyverno.io clustercleanuppolicies.kyverno.io \
           admissionreports.kyverno.io clusteradmissionreports.kyverno.io; do
  wait_for "CRD ${crd}" 60 3 -- crd_exists "${crd}" || log_warn "CRD ${crd} not confirmed — exact CRD names can shift between chart versions; cross-check 'kubectl get crd | grep kyverno.io' against docs/02-architecture-and-internals.md."
done

for deploy in kyverno-admission-controller kyverno-background-controller kyverno-cleanup-controller kyverno-reports-controller; do
  wait_for "Deployment ${deploy} rolled out" "${INSTALL_WAIT_TIMEOUT_SECONDS}" 5 -- deployment_rollout_ready "${KYVERNO_NAMESPACE}" "${deploy}" 10
done

wait_for "At least one Kyverno validating webhook configuration present" "${WEBHOOK_WAIT_TIMEOUT_SECONDS}" 5 -- \
  any_kyverno_webhook_exists validating || log_warn "No validating webhook found within timeout — check 'kubectl get validatingwebhookconfigurations | grep kyverno' manually."
wait_for "At least one Kyverno mutating webhook configuration present" "${WEBHOOK_WAIT_TIMEOUT_SECONDS}" 5 -- \
  any_kyverno_webhook_exists mutating || log_warn "No mutating webhook found within timeout — check 'kubectl get mutatingwebhookconfigurations | grep kyverno' manually."

log_pass "Kyverno installation complete. Run 'make validate-installation' next."
