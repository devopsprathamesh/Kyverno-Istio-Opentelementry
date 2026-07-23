#!/usr/bin/env bash
# Comprehensive runtime installation validation. Requires Kyverno already
# installed by scripts/install.sh against a cluster already confirmed by
# scripts/verify-cluster.sh. Prints PASS/WARN/FAIL, exits non-zero if any
# mandatory check fails. Never creates or modifies infrastructure beyond
# the small, cleaned-up admission-request/report probes described below.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl

FAIL_COUNT=0
check() {
  local description="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then
    log_pass "${description}"
  else
    log_fail "${description}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}
check_warn() {
  local description="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then
    log_pass "${description}"
  else
    log_warn "${description}"
  fi
}

log_section "Kyverno installation validation"

check "Kubernetes API reachable" -- kube_reachable
check "Namespace '${KYVERNO_NAMESPACE}' exists" -- namespace_exists "${KYVERNO_NAMESPACE}"
check "Helm release 'kyverno' exists" -- helm_release_exists kyverno "${KYVERNO_NAMESPACE}"

for deploy in kyverno-admission-controller kyverno-background-controller kyverno-cleanup-controller kyverno-reports-controller; do
  check "Deployment ${deploy} available" -- deployment_rollout_ready "${KYVERNO_NAMESPACE}" "${deploy}" 5
done

for crd in clusterpolicies.kyverno.io policies.kyverno.io policyexceptions.kyverno.io \
           cleanuppolicies.kyverno.io clustercleanuppolicies.kyverno.io; do
  check "CRD ${crd} exists" -- crd_exists "${crd}"
done

check "At least one validating webhook configuration exists" -- any_kyverno_webhook_exists validating
check "At least one mutating webhook configuration exists" -- any_kyverno_webhook_exists mutating

WEBHOOK_SVC="kyverno-svc"
check_warn "Webhook service '${WEBHOOK_SVC}' has ready endpoints" -- webhook_service_endpoints_ready "${KYVERNO_NAMESPACE}" "${WEBHOOK_SVC}"

check_warn "Admission controller logs show no obvious critical startup errors" -- \
  bash -c '! pod_logs_have_critical_errors "'"${KYVERNO_NAMESPACE}"'" "app.kubernetes.io/component=admission-controller"'

log_section "Functional probes (temporary, cleaned up automatically)"

PROBE_NS="${TEMP_NAMESPACE_PREFIX}validate-$(date +%s)"
cleanup() { kubectl delete namespace "${PROBE_NS}" --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl create namespace "${PROBE_NS}" --dry-run=client -o yaml \
  | kubectl label -f - "${LAB_RESOURCE_LABEL_KEY}=${LAB_RESOURCE_LABEL_VALUE}" --local -o yaml \
  | kubectl apply -f - >/dev/null

# 1. Kyverno can process a test admission request at all (a trivial,
#    unpoliced ConfigMap create should simply succeed).
check "Kyverno processes a test admission request without error" -- \
  kubectl create configmap admission-probe -n "${PROBE_NS}" --from-literal=probe=true

# 2. An audit-mode policy generates a report (uses the lab's own
#    require-labels audit policy from policies/audit/).
kubectl apply -f "${MODULE_ROOT}/policies/audit/require-labels-audit.yaml" >/dev/null
kubectl run audit-probe-pod -n "${PROBE_NS}" --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null 2>&1 || true
check_warn "Audit policy generates a PolicyReport entry" -- \
  wait_for "PolicyReport present in ${PROBE_NS}" "${REPORT_WAIT_TIMEOUT_SECONDS}" 5 -- \
  bash -c "kubectl get policyreport -n ${PROBE_NS} --no-headers 2>/dev/null | grep -q ."
kubectl delete -f "${MODULE_ROOT}/policies/audit/require-labels-audit.yaml" >/dev/null 2>&1 || true

# 3. An enforce-mode policy rejects a noncompliant resource.
kubectl apply -f "${MODULE_ROOT}/policies/validate/require-labels-enforce.yaml" >/dev/null
if kubectl run enforce-probe-pod -n "${PROBE_NS}" --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null 2>&1; then
  log_fail "Enforce policy did NOT reject a noncompliant pod as expected."
  FAIL_COUNT=$((FAIL_COUNT + 1))
  kubectl delete pod enforce-probe-pod -n "${PROBE_NS}" >/dev/null 2>&1 || true
else
  log_pass "Enforce policy correctly rejected a noncompliant resource."
fi
kubectl delete -f "${MODULE_ROOT}/policies/validate/require-labels-enforce.yaml" >/dev/null 2>&1 || true

# 4. A mutate policy changes a resource (adds a default label).
kubectl apply -f "${MODULE_ROOT}/policies/mutate/add-default-labels.yaml" >/dev/null
kubectl run mutate-probe-pod -n "${PROBE_NS}" --image=registry.k8s.io/pause:3.10 --restart=Never \
  --labels="app.kubernetes.io/name=mutate-probe" >/dev/null
MUTATED_VALUE="$(kubectl get pod mutate-probe-pod -n "${PROBE_NS}" -o jsonpath='{.metadata.labels.environment}' 2>/dev/null || true)"
if [ -n "${MUTATED_VALUE}" ]; then
  log_pass "Mutate policy added the expected default label (environment=${MUTATED_VALUE})."
else
  log_fail "Mutate policy did not add the expected default label."
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
kubectl delete -f "${MODULE_ROOT}/policies/mutate/add-default-labels.yaml" >/dev/null 2>&1 || true

# 5. A generate policy creates a resource (default-deny NetworkPolicy on
#    a labeled namespace).
kubectl apply -f "${MODULE_ROOT}/policies/generate/default-network-policy.yaml" >/dev/null
kubectl label namespace "${PROBE_NS}" generate-default-networkpolicy=enabled --overwrite >/dev/null
check_warn "Generate policy created a NetworkPolicy in ${PROBE_NS}" -- \
  wait_for "NetworkPolicy present in ${PROBE_NS}" "${REPORT_WAIT_TIMEOUT_SECONDS}" 5 -- \
  bash -c "kubectl get networkpolicy -n ${PROBE_NS} --no-headers 2>/dev/null | grep -q ."
kubectl delete -f "${MODULE_ROOT}/policies/generate/default-network-policy.yaml" >/dev/null 2>&1 || true

# 6. PolicyException scoping — confirmed narrow (see lab-10 /
#    policies/exceptions/*) rather than re-probed live here; this probe
#    only confirms the CRD and one lab exception apply cleanly.
check "PolicyException CRD (policyexceptions.kyverno.io) usable" -- \
  kubectl apply --dry-run=server -f "${MODULE_ROOT}/policies/exceptions/allow-demo-hostpath-exception.yaml"

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "validate-installation: ${FAIL_COUNT} mandatory check(s) failed."
  exit 1
fi
log_pass "validate-installation: all mandatory checks passed."
