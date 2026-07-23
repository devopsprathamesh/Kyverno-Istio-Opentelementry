#!/usr/bin/env bash
# Host-side prerequisite check for this module specifically: required
# CLI tools (kubectl, helm, kyverno CLI), and — unlike
# auto-setup-default-kube-env's version — this module does NOT check for
# or create a Kubernetes cluster; that is scripts/verify-cluster.sh's job.
# Read-only. Never installs anything.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

log_section "Kyverno lab prerequisite check"

FAIL_COUNT=0
pass() { log_pass "$1"; }
warn() { log_warn "$1"; }
fail() { log_fail "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for cmd in kubectl helm git make curl; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    VERSION_LINE="$("${cmd}" version 2>/dev/null | head -1 || "${cmd}" --version 2>/dev/null | head -1 || true)"
    pass "'${cmd}' is installed (${VERSION_LINE})"
  else
    fail "'${cmd}' is not installed or not on PATH. See docs/labs/lab-00-prerequisites.md."
  fi
done

if command -v kyverno >/dev/null 2>&1; then
  KYVERNO_CLI_INSTALLED_VERSION="$(kyverno version 2>/dev/null | head -3 || true)"
  pass "Kyverno CLI is installed:"
  log_info "${KYVERNO_CLI_INSTALLED_VERSION}"
else
  warn "Kyverno CLI ('kyverno') is not installed — offline policy testing ('make test-static', 'kyverno apply', 'kyverno test') will be skipped. See labs/lab-00-prerequisites.md 'Installing the Kyverno CLI'. Not required for cluster installation itself."
fi

if command -v cosign >/dev/null 2>&1; then
  pass "cosign is installed (optional — only used if lab-11's ENABLE_COSIGN_RUNTIME_LAB=true)"
else
  log_info "cosign not installed — lab 11's optional runtime signing path will be skipped gracefully; its static/offline path does not need it."
fi

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "Prerequisite check failed: ${FAIL_COUNT} mandatory check(s) did not pass."
  exit 1
fi
log_pass "All mandatory prerequisite checks passed."
log_info "Next: run 'make verify-cluster' to confirm this is the intended local lab cluster before installing anything."
