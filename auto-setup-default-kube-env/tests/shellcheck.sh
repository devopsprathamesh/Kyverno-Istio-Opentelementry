#!/usr/bin/env bash
# Static check: `bash -n` (syntax) and ShellCheck (lint) on every shell
# script in this module. Never modifies anything. Exits non-zero only
# if a `bash -n` syntax error is found or ShellCheck reports errors
# (warnings are printed but do not fail the run).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${MODULE_ROOT}"

FAIL=0
mapfile -t SCRIPTS < <(find scripts -type f -name '*.sh' | sort)
SCRIPTS+=("tests/shellcheck.sh" "tests/vagrant-validation.sh" "tests/cluster-smoke-test.sh" "tests/network-test.sh" "tests/storage-test.sh")

echo "==> bash -n (syntax check) on ${#SCRIPTS[@]} scripts"
for f in "${SCRIPTS[@]}"; do
  if bash -n "${f}"; then
    echo "[PASS] bash -n ${f}"
  else
    echo "[FAIL] bash -n ${f}"
    FAIL=1
  fi
done

echo
if command -v shellcheck >/dev/null 2>&1; then
  echo "==> shellcheck on ${#SCRIPTS[@]} scripts (severity: warning+; SC1091 excluded — every"
  echo "    'source' target in this module is computed from MODULE_ROOT at runtime, which"
  echo "    ShellCheck cannot statically follow even with -x; each is annotated with a"
  echo "    '# shellcheck source=' hint for editor tooling instead)"
  for f in "${SCRIPTS[@]}"; do
    if shellcheck -x --severity=warning -e SC1091 "${f}"; then
      echo "[PASS] shellcheck ${f}"
    else
      echo "[FAIL] shellcheck ${f}"
      FAIL=1
    fi
  done
else
  echo "[WARN] shellcheck is not installed on this host — only 'bash -n' syntax checks were run, not lint checks. Install shellcheck (apt-get install shellcheck / brew install shellcheck) to get full linting."
fi

exit "${FAIL}"
