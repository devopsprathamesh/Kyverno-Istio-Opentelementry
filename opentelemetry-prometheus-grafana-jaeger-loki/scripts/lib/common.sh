#!/usr/bin/env bash
# Shared bootstrap for every script in this module: locates MODULE_ROOT,
# loads config/*.env, and provides small generic helpers. Source this
# file, never execute it directly.
set -euo pipefail

_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${_COMMON_SH_DIR}/../.." && pwd)"
export MODULE_ROOT

# shellcheck source=./logging.sh
source "${_COMMON_SH_DIR}/logging.sh"

# shellcheck source=../../config/versions.env
source "${MODULE_ROOT}/config/versions.env"
# shellcheck source=../../config/namespaces.env
source "${MODULE_ROOT}/config/namespaces.env"
# shellcheck source=../../config/lab-settings.env
source "${MODULE_ROOT}/config/lab-settings.env"
# shellcheck source=../../config/endpoints.env
source "${MODULE_ROOT}/config/endpoints.env"
# shellcheck source=../../config/retention.env
source "${MODULE_ROOT}/config/retention.env"

GENERATED_DIR="${MODULE_ROOT}/.generated"

ensure_generated_dir() {
  mkdir -p "${GENERATED_DIR}"
  chmod 700 "${GENERATED_DIR}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log_fatal "Required command '${cmd}' not found on PATH. See labs/lab-00-prerequisites.md."
  fi
}

# retry N SLEEP_SECONDS -- CMD [ARGS...]
retry() {
  local attempts="$1" sleep_seconds="$2"
  shift 2
  [ "$1" = "--" ] && shift
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

profile_arg() {
  local profile="${LAB_PROFILE:-${DEFAULT_LAB_PROFILE}}"
  case " ${VALID_LAB_PROFILES} " in
    *" ${profile} "*) echo "${profile}" ;;
    *) log_fatal "Invalid LAB_PROFILE='${profile}'. Valid values: ${VALID_LAB_PROFILES}" ;;
  esac
}
