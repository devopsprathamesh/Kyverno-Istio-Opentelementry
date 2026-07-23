#!/usr/bin/env bash
# Host-side prerequisite check for this module: required CLI tools
# (kubectl, helm, istioctl). Unlike auto-setup-default-kube-env's
# version, this module does NOT check for or create a Kubernetes
# cluster — that is scripts/verify-cluster.sh's job. Read-only. Never
# installs anything.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

log_section "Istio lab prerequisite check"

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

if command -v istioctl >/dev/null 2>&1; then
  ISTIOCTL_INSTALLED_VERSION="$(istioctl version --remote=false 2>/dev/null || true)"
  pass "istioctl is installed: ${ISTIOCTL_INSTALLED_VERSION}"
else
  warn "istioctl is not installed — 'make install', 'istioctl analyze', and most of 'make test-static' will not work. See labs/lab-00-prerequisites.md 'Installing istioctl'."
fi

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "Prerequisite check failed: ${FAIL_COUNT} mandatory check(s) did not pass."
  exit 1
fi
log_pass "All mandatory prerequisite checks passed."
log_info "Next: run 'make verify-cluster' to confirm this is the intended local lab cluster, with healthy Cilium/kube-proxy/CoreDNS, before installing anything."
