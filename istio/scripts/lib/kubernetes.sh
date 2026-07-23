#!/usr/bin/env bash
# kubectl/helm helpers shared by this module's scripts. Source this
# file, never execute it directly. Assumes common.sh has already been
# sourced.
#
# Every "does X exist / match Y" helper here captures command output
# into a variable before matching it, rather than piping a producer
# straight into `grep -q`. Under `set -o pipefail` (mandatory in this
# repository), `producer | grep -q pattern` can spuriously report
# failure via SIGPIPE — a real bug found and fixed in
# auto-setup-default-kube-env during Phase 2 (see root
# docs/VALIDATION-STATUS.md Phase 2 detail for the full story).
set -euo pipefail

kube_reachable() {
  kubectl get --raw=/healthz >/dev/null 2>&1
}

current_context() {
  kubectl config current-context 2>/dev/null || true
}

current_api_server() {
  kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true
}

node_names() {
  kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true
}

crd_exists() {
  kubectl get crd "$1" >/dev/null 2>&1
}

resource_exists() {
  local kind="$1" name="$2" namespace="${3:-}"
  if [ -n "${namespace}" ]; then
    kubectl get "${kind}" "${name}" -n "${namespace}" >/dev/null 2>&1
  else
    kubectl get "${kind}" "${name}" >/dev/null 2>&1
  fi
}

namespace_exists() {
  kubectl get namespace "$1" >/dev/null 2>&1
}

helm_release_exists() {
  helm status "$1" --namespace "$2" >/dev/null 2>&1
}

deployment_rollout_ready() {
  kubectl -n "$1" rollout status deployment/"$2" --timeout="${3}s" >/dev/null 2>&1
}

daemonset_ready() {
  # daemonset_ready NAMESPACE NAME
  local desired ready
  desired="$(kubectl -n "$1" get daemonset "$2" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo -1)"
  ready="$(kubectl -n "$1" get daemonset "$2" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo -2)"
  [ -n "${desired}" ] && [ "${desired}" = "${ready}" ] && [ "${desired}" != "0" ]
}

any_webhook_exists() {
  # any_webhook_exists validating|mutating NAME_PREFIX
  local kind_plural names
  case "$1" in
    validating) kind_plural="validatingwebhookconfigurations" ;;
    mutating) kind_plural="mutatingwebhookconfigurations" ;;
    *) log_fatal "any_webhook_exists: first argument must be 'validating' or 'mutating'" ;;
  esac
  names="$(kubectl get "${kind_plural}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  grep -q "$2" <<<"${names}"
}

# wait_for DESCRIPTION TIMEOUT_SECONDS INTERVAL_SECONDS -- CHECK_CMD [ARGS...]
wait_for() {
  local description="$1" timeout_seconds="$2" interval_seconds="$3"
  shift 3
  [ "$1" = "--" ] && shift
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

pod_logs_have_critical_errors() {
  local namespace="$1" selector="$2" logs
  logs="$(kubectl -n "${namespace}" logs -l "${selector}" --tail=200 --all-containers 2>/dev/null || true)"
  grep -qiE 'panic:|fatal error|failed to start|unable to start' <<<"${logs}"
}
