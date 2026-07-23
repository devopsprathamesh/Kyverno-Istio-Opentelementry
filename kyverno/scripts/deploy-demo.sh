#!/usr/bin/env bash
# Creates the kyverno-demo namespace and deploys the demo workload set
# (applications/, insecure-workloads/, compliant-workloads/). Does NOT
# apply any policy — policies are applied separately via apply-policies.sh
# or individual lab instructions, so learners can observe insecure
# workloads existing un-enforced before turning policies on (this is
# deliberate — see labs/lab-02-audit-vs-enforce.md).
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

log_section "Deploying demo workloads to ${DEMO_NAMESPACE}"

kubectl apply -f "${MODULE_ROOT}/demo/namespace.yaml"
log_pass "Namespace '${DEMO_NAMESPACE}' ensured."

for dir in applications compliant-workloads insecure-workloads; do
  path="${MODULE_ROOT}/demo/${dir}"
  if [ -d "${path}" ] && [ -n "$(ls -A "${path}" 2>/dev/null)" ]; then
    kubectl apply -f "${path}" -n "${DEMO_NAMESPACE}"
    log_pass "Applied demo/${dir}/"
  fi
done

log_info "Insecure workloads are intentionally deployed WITHOUT policy enforcement yet — see labs/lab-02-audit-vs-enforce.md to observe them get flagged (audit) and then rejected (enforce)."
log_pass "Demo deployment complete."
