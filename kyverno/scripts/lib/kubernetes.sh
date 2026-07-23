#!/usr/bin/env bash
# kubectl/helm helpers shared by this module's scripts. Source this
# file, never execute it directly. Assumes common.sh has already been
# sourced (for logging + config).
#
# Every "does X exist / match Y" helper here captures command output
# into a variable before matching it, rather than piping a producer
# straight into `grep -q`. Under `set -o pipefail` (mandatory in this
# repository), `producer | grep -q pattern` can spuriously report
# failure: grep -q exits as soon as it finds a match, which can close
# the pipe while the producer is still mid-write, delivering it a
# SIGPIPE that makes the pipeline's exit status reflect that kill
# instead of grep's real, successful match. This was an actual bug
# found and fixed in auto-setup-default-kube-env during Phase 2 — see
# docs/VALIDATION-STATUS.md's Phase 2 detail for the full story.
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
  # resource_exists KIND NAME [NAMESPACE]
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
  # helm_release_exists RELEASE NAMESPACE
  helm status "$1" --namespace "$2" >/dev/null 2>&1
}

deployment_rollout_ready() {
  # deployment_rollout_ready NAMESPACE NAME TIMEOUT_SECONDS
  kubectl -n "$1" rollout status deployment/"$2" --timeout="${3}s" >/dev/null 2>&1
}

webhook_exists() {
  # webhook_exists validating|mutating NAME
  local kind_plural
  case "$1" in
    validating) kind_plural="validatingwebhookconfigurations" ;;
    mutating) kind_plural="mutatingwebhookconfigurations" ;;
    *) log_fatal "webhook_exists: first argument must be 'validating' or 'mutating'" ;;
  esac
  kubectl get "${kind_plural}" "$2" >/dev/null 2>&1
}

# any_kyverno_webhook_exists validating|mutating — discovery-based check
# (any webhook configuration whose name starts with "kyverno-"), used
# instead of an exact-name check where the precise webhook config name
# is a Kyverno-internal implementation detail that can shift between
# chart versions (see docs/02-architecture-and-internals.md's note on
# verifying current resource names against the pinned version).
any_kyverno_webhook_exists() {
  local kind_plural names
  case "$1" in
    validating) kind_plural="validatingwebhookconfigurations" ;;
    mutating) kind_plural="mutatingwebhookconfigurations" ;;
    *) log_fatal "any_kyverno_webhook_exists: first argument must be 'validating' or 'mutating'" ;;
  esac
  names="$(kubectl get "${kind_plural}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  grep -q 'kyverno' <<<"${names}"
}

webhook_service_endpoints_ready() {
  # webhook_service_endpoints_ready NAMESPACE SERVICE_NAME
  local addresses
  addresses="$(kubectl -n "$1" get endpoints "$2" -o jsonpath='{.subsets[*].addresses}' 2>/dev/null || true)"
  [ -n "${addresses}" ] && [ "${addresses}" != "[]" ]
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

# pod_logs_have_critical_errors NAMESPACE LABEL_SELECTOR — best-effort scan
# of recent logs for obvious startup failures; used as a WARN-only signal,
# never a hard FAIL, since "critical" log-line heuristics are inherently
# approximate.
pod_logs_have_critical_errors() {
  local namespace="$1" selector="$2" logs
  logs="$(kubectl -n "${namespace}" logs -l "${selector}" --tail=200 --all-containers 2>/dev/null || true)"
  grep -qiE 'panic:|fatal error|failed to start|unable to create controller' <<<"${logs}"
}
