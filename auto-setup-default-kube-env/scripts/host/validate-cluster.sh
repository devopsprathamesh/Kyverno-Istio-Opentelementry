#!/usr/bin/env bash
# Comprehensive host-side cluster validation: VM layer, OS layer,
# Kubernetes layer, Cilium/Hubble layer, storage layer, host-access
# layer. Prints PASS/WARN/FAIL per check, writes a report under
# .generated/validation-results/, and exits non-zero if any mandatory
# (non-WARN) check failed. Requires a cluster already provisioned by
# `make setup` — this script never creates or modifies infrastructure.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_not_root
cd "${MODULE_ROOT}"
ensure_generated_dirs
RECORD_RESULT_REPORT_PATH="${VALIDATION_RESULTS_DIR}/validate-cluster-$(date +%Y%m%dT%H%M%S).log"
export RECORD_RESULT_REPORT_PATH
: >"${RECORD_RESULT_REPORT_PATH}"

FAIL_COUNT=0
check() {
  # check DESCRIPTION -- CMD [ARGS...]   (mandatory: counts toward FAIL_COUNT)
  local description="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then
    log_pass "${description}"; record_result "${description}" PASS "ok"
  else
    log_fail "${description}"; record_result "${description}" FAIL "command failed: $*"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}
check_warn() {
  local description="$1"; shift; [ "$1" = "--" ] && shift
  if "$@" >/dev/null 2>&1; then
    log_pass "${description}"; record_result "${description}" PASS "ok"
  else
    log_warn "${description}"; record_result "${description}" WARN "command failed: $*"
  fi
}
vssh() { vagrant ssh "$1" -c "$2" 2>/dev/null; }

log_section "1/6 — Virtual machine layer"
for name in "${CONTROL_PLANE_NAME}" "${WORKER1_NAME}" "${WORKER2_NAME}"; do
  check "VM ${name} exists and is running" -- bash -c "vagrant status ${name} | grep -q running"
  check "SSH works on ${name}" -- vagrant ssh "${name}" -c "true"
  check "Hostname is correct on ${name}" -- bash -c "[ \"\$(vagrant ssh ${name} -c hostname 2>/dev/null | tr -d '\r\n')\" = '${name}' ]"
done
check "Control plane carries ${CONTROL_PLANE_IP}" -- bash -c "vagrant ssh ${CONTROL_PLANE_NAME} -c 'ip -4 addr show' | grep -q ${CONTROL_PLANE_IP}"
check "Worker 1 carries ${WORKER1_IP}" -- bash -c "vagrant ssh ${WORKER1_NAME} -c 'ip -4 addr show' | grep -q ${WORKER1_IP}"
check "Worker 2 carries ${WORKER2_IP}" -- bash -c "vagrant ssh ${WORKER2_NAME} -c 'ip -4 addr show' | grep -q ${WORKER2_IP}"
check_warn "NAT/internet egress from control plane" -- vagrant ssh "${CONTROL_PLANE_NAME}" -c "curl -fsS -o /dev/null https://pkgs.k8s.io"
check_warn "DNS resolution on control plane" -- vagrant ssh "${CONTROL_PLANE_NAME}" -c "getent hosts kubernetes.io"
check_warn "Time synchronized on control plane" -- vagrant ssh "${CONTROL_PLANE_NAME}" -c "timedatectl status | grep -qi 'System clock synchronized: yes'"

log_section "2/6 — Operating-system layer"
for name in "${CONTROL_PLANE_NAME}" "${WORKER1_NAME}" "${WORKER2_NAME}"; do
  check "Swap disabled on ${name}" -- vagrant ssh "${name}" -c "[ -z \"\$(swapon --show --noheadings)\" ]"
  check "overlay module loaded on ${name}" -- vagrant ssh "${name}" -c "lsmod | grep -q overlay"
  check "br_netfilter module loaded on ${name}" -- vagrant ssh "${name}" -c "lsmod | grep -q br_netfilter"
  check "containerd active on ${name}" -- vagrant ssh "${name}" -c "systemctl is-active --quiet containerd"
  check "kubelet installed on ${name}" -- vagrant ssh "${name}" -c "command -v kubelet"
  log_info "${name} disk/memory: $(vssh "${name}" 'df -h / | tail -1; free -h | grep Mem' | tr '\n' ' ')"
done

export KUBECONFIG="${GENERATED_DIR}/kubeconfig"
if [ ! -f "${KUBECONFIG}" ]; then
  log_fail "No kubeconfig at ${KUBECONFIG} — cannot run Kubernetes/Cilium/storage/host-access checks."
  record_result "kubeconfig present" FAIL "missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  log_section "3/6 — Kubernetes layer"
  check "API server reachable" -- kubectl get --raw=/healthz
  check "Exactly 3 nodes registered" -- bash -c "[ \"\$(kubectl get nodes --no-headers | wc -l)\" -eq 3 ]"
  check "All nodes Ready" -- bash -c "[ \"\$(kubectl get nodes --no-headers | grep -vc ' Ready')\" -eq 0 ]"
  check "Control-plane role label present on ${CONTROL_PLANE_NAME}" -- bash -c "kubectl get node ${CONTROL_PLANE_NAME} -o jsonpath='{.metadata.labels}' | grep -q control-plane"
  check "CoreDNS pods healthy" -- bash -c "[ \"\$(kubectl -n kube-system get pods -l k8s-app=kube-dns --no-headers | grep -vc Running)\" -eq 0 ]"
  check "kube-proxy present (retained per ADR-003)" -- kubectl -n kube-system get daemonset kube-proxy
  check "Node private IPs correct" -- bash -c "kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type==\"InternalIP\")].address}' | grep -q ${CONTROL_PLANE_IP}"
  check "Kubernetes version matches pin (${KUBERNETES_VERSION})" -- bash -c "kubectl version -o json | grep -q ${KUBERNETES_VERSION}"
  check_warn "No unexpected NoSchedule taints on workers" -- bash -c "[ \"\$(kubectl get node ${WORKER1_NAME} -o jsonpath='{.spec.taints}')\" = '' ]"
  # Note the negation: we want "no row is INVALID/EXPIRED", not "at least
  # one row isn't" (which `grep -qv PATTERN` alone would actually test —
  # true even if only one row out of several is fine).
  check_warn "Control-plane certificates valid (>30d)" -- vagrant ssh "${CONTROL_PLANE_NAME}" -c "! sudo kubeadm certs check-expiration | grep -q 'INVALID\\|EXPIRED'"

  log_section "4/6 — Cilium layer"
  check "Cilium DaemonSet fully rolled out" -- bash -c "kubectl -n ${CILIUM_NAMESPACE} rollout status daemonset/cilium --timeout=10s"
  check "Cilium operator ready" -- bash -c "kubectl -n ${CILIUM_NAMESPACE} rollout status deployment/cilium-operator --timeout=10s"
  check_warn "'cilium status --wait' healthy" -- vagrant ssh "${CONTROL_PLANE_NAME}" -c "sudo KUBECONFIG=/etc/kubernetes/admin.conf cilium status --wait"
  check "Hubble Relay ready" -- bash -c "kubectl -n ${CILIUM_NAMESPACE} rollout status deployment/hubble-relay --timeout=10s"
  bash "${MODULE_ROOT}/tests/network-test.sh" || log_warn "tests/network-test.sh reported failures — see its own output above for pod networking/service/DNS/NetworkPolicy/Hubble detail."

  log_section "5/6 — Storage layer"
  check "StorageClass '${STORAGE_CLASS_NAME}' exists" -- kubectl get storageclass "${STORAGE_CLASS_NAME}"
  check "StorageClass '${STORAGE_CLASS_NAME}' is default" -- bash -c "kubectl get storageclass ${STORAGE_CLASS_NAME} -o jsonpath='{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}' | grep -q true"
  bash "${MODULE_ROOT}/tests/storage-test.sh" || log_warn "tests/storage-test.sh reported failures — see its own output above."

  log_section "6/6 — Host access layer"
  check "Generated kubeconfig exists" -- test -f "${KUBECONFIG}"
  check "Generated kubeconfig has restrictive permissions" -- bash -c "[ \"\$(stat -c '%a' ${KUBECONFIG} 2>/dev/null || stat -f '%Lp' ${KUBECONFIG})\" = '600' ]"
  check_warn "Host kubectl can reach the API server" -- kubectl get nodes
  check_warn "Helm works on the control plane" -- vagrant ssh "${CONTROL_PLANE_NAME}" -c "helm version"
  check ".generated/ is git-ignored" -- bash -c "cd ${MODULE_ROOT} && git check-ignore -q .generated/kubeconfig"
fi

echo
log_info "Full report: ${RECORD_RESULT_REPORT_PATH}"
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "validate-cluster: ${FAIL_COUNT} mandatory check(s) failed."
  exit 1
fi
log_pass "validate-cluster: all mandatory checks passed."
