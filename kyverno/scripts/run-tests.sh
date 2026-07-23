#!/usr/bin/env bash
# Runs the full runtime test suite (tests/installation-test.sh plus every
# tests/*-policy-tests.sh script). Requires Kyverno installed and demo
# workloads deployed. Static (cluster-free) tests live in
# tests/static-validation.sh instead — see 'make test-static'.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_fatal "No reachable cluster. Run 'make verify-cluster' first."
fi

log_section "Runtime test suite"

FAIL=0
for t in installation-test validate-policy-tests mutate-policy-tests generate-policy-tests \
         cleanup-policy-tests exception-tests image-verification-tests; do
  script="${MODULE_ROOT}/tests/${t}.sh"
  if [ -f "${script}" ]; then
    log_section "Running tests/${t}.sh"
    if ! bash "${script}"; then
      log_fail "tests/${t}.sh reported failures."
      FAIL=1
    fi
  fi
done

echo
if [ "${FAIL}" -ne 0 ]; then
  log_fail "run-tests: one or more test scripts reported failures."
  exit 1
fi
log_pass "run-tests: all runtime test scripts passed."
