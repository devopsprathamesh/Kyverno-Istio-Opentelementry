#!/usr/bin/env bash
# Idempotency and state-check helpers, shared by guest provisioning
# scripts (to decide whether an install step is already done) and host
# validation scripts (to check PASS/WARN/FAIL conditions). Source this
# file, never execute it directly. Assumes common.sh has already been
# sourced.

set -euo pipefail

is_swap_disabled() {
  [ -z "$(swapon --show --noheadings 2>/dev/null)" ]
}

is_kernel_module_loaded() {
  # Captures lsmod's output before matching, rather than piping it
  # straight into `grep -q`. Under `set -o pipefail` (mandatory in this
  # module), `producer | grep -q pattern` can spuriously report failure
  # when grep exits immediately after its first match — closing its end
  # of the pipe while the producer (lsmod, here) is still mid-write,
  # which delivers it a SIGPIPE and makes the pipeline's exit status
  # reflect that kill rather than grep's actual (successful) match.
  local module="$1" loaded_modules
  loaded_modules="$(lsmod | awk '{print $1}')"
  grep -qx -- "${module}" <<<"${loaded_modules}"
}

is_sysctl_set() {
  local key="$1" expected="$2"
  [ "$(sysctl -n "${key}" 2>/dev/null)" = "${expected}" ]
}

is_containerd_active() {
  systemctl is-active --quiet containerd
}

is_kubelet_installed() {
  command -v kubelet >/dev/null 2>&1
}

# True once `kubeadm init` has successfully completed on this node.
is_control_plane_initialized() {
  [ -f /etc/kubernetes/admin.conf ]
}

# True once this node (control-plane or worker) has a kubelet.conf,
# i.e. it has either been kubeadm-init'd or successfully joined.
is_node_joined() {
  [ -f /etc/kubernetes/kubelet.conf ]
}

is_helm_release_installed() {
  local release="$1" namespace="$2"
  helm status "${release}" --namespace "${namespace}" >/dev/null 2>&1
}

k8s_object_exists() {
  # k8s_object_exists KUBECONFIG_PATH KIND NAME [NAMESPACE]
  local kubeconfig="$1" kind="$2" name="$3" namespace="${4:-}"
  if [ -n "${namespace}" ]; then
    KUBECONFIG="${kubeconfig}" kubectl get "${kind}" "${name}" -n "${namespace}" >/dev/null 2>&1
  else
    KUBECONFIG="${kubeconfig}" kubectl get "${kind}" "${name}" >/dev/null 2>&1
  fi
}

# wait_for DESCRIPTION TIMEOUT_SECONDS INTERVAL_SECONDS -- CHECK_CMD [ARGS...]
# Polls CHECK_CMD until it exits 0 or TIMEOUT_SECONDS elapses.
wait_for() {
  local description="$1" timeout_seconds="$2" interval_seconds="$3"
  shift 3
  if [ "$1" = "--" ]; then shift; fi
  local waited=0
  log_info "Waiting for: ${description} (timeout ${timeout_seconds}s)"
  while ! "$@" >/dev/null 2>&1; do
    if [ "${waited}" -ge "${timeout_seconds}" ]; then
      log_fail "Timed out waiting for: ${description}"
      return 1
    fi
    sleep "${interval_seconds}"
    waited=$((waited + interval_seconds))
  done
  log_pass "${description}"
}

# record_result NAME STATUS(PASS|WARN|FAIL) DETAIL — append a line to the
# host-side validation report under .generated/validation-results/.
# Never call this with anything that could contain a secret.
record_result() {
  local name="$1" status="$2" detail="$3"
  ensure_generated_dirs
  local report
  report="${VALIDATION_RESULTS_DIR}/validate-cluster-$(date +%Y%m%dT%H%M%S).log"
  RECORD_RESULT_REPORT_PATH="${RECORD_RESULT_REPORT_PATH:-${report}}"
  printf '[%s] %-4s %s\n' "$(_log_ts)" "${status}" "${name}: ${detail}" >>"${RECORD_RESULT_REPORT_PATH}"
}
