#!/usr/bin/env bash
# Removes only the contents of .generated/ (kubeconfig, join command,
# rendered templates, validation reports). Never touches tracked files.
# This is NOT a cluster teardown — it does not destroy VMs or the
# cluster itself; use `make destroy` / `make reset-cluster` for that.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

require_not_root

if [ -d "${GENERATED_DIR}" ]; then
  log_info "Removing contents of ${GENERATED_DIR} (kubeconfig, join command, rendered templates, validation reports)."
  find "${GENERATED_DIR}" -mindepth 1 -delete
  log_pass "Cleaned ${GENERATED_DIR}. The cluster itself is untouched — this only removes locally generated files."
else
  log_info "${GENERATED_DIR} does not exist, nothing to clean."
fi
