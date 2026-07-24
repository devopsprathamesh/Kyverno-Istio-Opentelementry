#!/usr/bin/env bash
# Host-side prerequisite check for this module: required CLI tools
# (kubectl, helm, curl, python3). Unlike auto-setup-default-kube-env's
# version, this module does NOT check for or create a Kubernetes
# cluster — that is scripts/verify-cluster.sh's job. Read-only. Never
# installs anything.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

log_section "Observability lab prerequisite check"

FAIL_COUNT=0
pass() { log_pass "$1"; }
warn() { log_warn "$1"; }
fail() { log_fail "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

for cmd in kubectl helm git make curl python3; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    VERSION_LINE="$("${cmd}" version 2>/dev/null | head -1 || "${cmd}" --version 2>/dev/null | head -1 || true)"
    pass "'${cmd}' is installed (${VERSION_LINE})"
  else
    fail "'${cmd}' is not installed or not on PATH. See labs/lab-00-prerequisites.md."
  fi
done

if command -v docker >/dev/null 2>&1; then
  pass "docker is installed — 'make build-demo-images' can build the demo application locally."
elif command -v podman >/dev/null 2>&1; then
  pass "podman is installed — 'make build-demo-images' can build the demo application locally (podman path)."
else
  warn "Neither docker nor podman is installed — 'make build-demo-images'/'make deploy-demo' will not work until one is available. Everything else (install-all, docs, labs) does not require a container builder. See labs/lab-00-prerequisites.md."
fi

if command -v vagrant >/dev/null 2>&1; then
  pass "vagrant is installed — 'make build-demo-images' can import built images directly into cluster nodes via 'vagrant ssh'."
else
  warn "vagrant is not installed — image import to cluster nodes (a step inside 'make build-demo-images') assumes vagrant ssh access to the base platform's VMs; see ../auto-setup-default-kube-env/README.md."
fi

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "Prerequisite check failed: ${FAIL_COUNT} mandatory check(s) did not pass."
  exit 1
fi
log_pass "All mandatory prerequisite checks passed."
log_info "Next: run 'make verify-cluster' to confirm this is the intended local lab cluster, with healthy Cilium/kube-proxy/CoreDNS, before installing anything."
