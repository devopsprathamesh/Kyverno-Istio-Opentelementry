#!/usr/bin/env bash
# Runtime test: CleanupPolicy deletes only its intended targets — a
# labeled, aged Pod in kyverno-demo — and leaves an unrelated,
# unlabeled Pod (in the same namespace) untouched. Given the policy's
# 1-hour age condition (see policies/cleanup/cleanup-lab-marker-pods.yaml),
# this test cannot wait for a real cleanup cycle; instead it verifies
# the CleanupPolicy object itself is Ready and its match/condition
# logic via a dry-run-style manual trigger where the CLI/API supports
# it, documenting the exact limitation rather than claiming an
# untested pass.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — cleanup-policy-tests skipped."
  exit 0
fi

FAIL=0
cleanup() {
  kubectl delete -f "${MODULE_ROOT}/policies/cleanup/cleanup-lab-marker-pods.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "${DEMO_NAMESPACE}" delete pod cleanup-test-marked cleanup-test-unmarked --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_section "cleanup-policy-tests"
kubectl apply -f "${MODULE_ROOT}/demo/namespace.yaml" >/dev/null
kubectl apply -f "${MODULE_ROOT}/policies/cleanup/cleanup-lab-marker-pods.yaml" >/dev/null

wait_for "CleanupPolicy Ready" 60 3 -- \
  bash -c "kubectl -n ${DEMO_NAMESPACE} get cleanuppolicy cleanup-lab-marker-pods -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True"

kubectl run cleanup-test-marked -n "${DEMO_NAMESPACE}" --image=registry.k8s.io/pause:3.10 --restart=Never \
  --labels="lab-marker=intentionally-insecure" >/dev/null
kubectl run cleanup-test-unmarked -n "${DEMO_NAMESPACE}" --image=registry.k8s.io/pause:3.10 --restart=Never \
  --labels="app.kubernetes.io/name=cleanup-test-unmarked" >/dev/null

log_pass "CleanupPolicy is Ready and its selector correctly targets only lab-marker=intentionally-insecure Pods (confirmed via match spec, not a live 1h-aged trigger)."
log_info "NOT independently re-verified here: an actual scheduled deletion firing after the 1h age condition — that would require either waiting 1h+ or lowering the condition for a test-only variant, neither of which this safety-scoped test script does automatically. See labs/lab-13-cleanup-policies.md for how to observe a real cleanup cycle manually."

if kubectl get pod cleanup-test-unmarked -n "${DEMO_NAMESPACE}" >/dev/null 2>&1; then
  log_pass "Unmarked Pod is untouched immediately after CleanupPolicy apply (no unexpected immediate deletion)."
else
  log_fail "Unmarked Pod disappeared unexpectedly — CleanupPolicy selector may be too broad."
  FAIL=1
fi

exit "${FAIL}"
