#!/usr/bin/env bash
# Shared bootstrap for every host and guest script in this module: locates
# MODULE_ROOT, loads config/*.env, and provides small generic helpers.
# Source this file, never execute it directly.

set -euo pipefail

# MODULE_ROOT resolution works identically on the host and inside a guest
# VM because Vagrant syncs this entire directory to /vagrant on each
# node, preserving the same scripts/config/... layout — see Vagrantfile.
_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${_COMMON_SH_DIR}/../.." && pwd)"
export MODULE_ROOT

# shellcheck source=./logging.sh
source "${_COMMON_SH_DIR}/logging.sh"

# shellcheck source=../../config/versions.env
source "${MODULE_ROOT}/config/versions.env"
# shellcheck source=../../config/cluster.env
source "${MODULE_ROOT}/config/cluster.env"
# shellcheck source=../../config/profiles.env
source "${MODULE_ROOT}/config/profiles.env"

GENERATED_DIR="${MODULE_ROOT}/.generated"
RENDERED_DIR="${GENERATED_DIR}/rendered"
VALIDATION_RESULTS_DIR="${GENERATED_DIR}/validation-results"

ensure_generated_dirs() {
  mkdir -p "${RENDERED_DIR}" "${VALIDATION_RESULTS_DIR}"
  chmod 700 "${GENERATED_DIR}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_fatal "Required command '${cmd}' not found on PATH."
  fi
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_fatal "This script must run as root (guest provisioning scripts run via Vagrant as root)."
  fi
}

require_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    log_fatal "This script is meant to run as your normal host user, not root."
  fi
}

# render_template SRC DEST — substitute ${VAR}-style placeholders in SRC
# using the current shell environment, writing the result to DEST.
# Requires envsubst (gettext-base), installed by 00-common.sh on guests.
render_template() {
  local src="$1" dest="$2"
  require_cmd envsubst
  mkdir -p "$(dirname "${dest}")"
  envsubst <"${src}" >"${dest}"
}

# retry N SLEEP_SECONDS -- CMD [ARGS...] — run CMD up to N times, sleeping
# SLEEP_SECONDS between attempts, until it succeeds or attempts run out.
retry() {
  local attempts="$1" sleep_seconds="$2"
  shift 2
  if [ "$1" = "--" ]; then shift; fi
  local n=1
  until "$@"; do
    if [ "${n}" -ge "${attempts}" ]; then
      log_fail "Command failed after ${attempts} attempts: $*"
      return 1
    fi
    log_warn "Attempt ${n}/${attempts} failed for: $* — retrying in ${sleep_seconds}s"
    sleep "${sleep_seconds}"
    n=$((n + 1))
  done
}

# node_ip_for NAME — resolve one of this module's fixed node IPs by name,
# used by guest scripts that need "my own" IP without re-deriving it.
node_ip_for() {
  case "$1" in
    "${CONTROL_PLANE_NAME}") echo "${CONTROL_PLANE_IP}" ;;
    "${WORKER1_NAME}") echo "${WORKER1_IP}" ;;
    "${WORKER2_NAME}") echo "${WORKER2_IP}" ;;
    *) log_fatal "node_ip_for: unknown node name '$1'" ;;
  esac
}
