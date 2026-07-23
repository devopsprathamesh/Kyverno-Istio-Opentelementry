#!/usr/bin/env bash
# Cluster-free static validation: everything that can be checked without
# a live Kubernetes cluster. Called by `make test-static`. Prints
# PASS/WARN/FAIL, records skipped-tool-unavailable checks explicitly
# rather than silently omitting them, and exits non-zero only on a
# mandatory FAIL.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

FAIL=0
pass() { log_pass "$1"; }
warn() { log_warn "$1"; }
fail() { log_fail "$1"; FAIL=1; }
skip() { log_info "[SKIP] $1"; }

log_section "1. bash -n and ShellCheck"
mapfile -t SCRIPTS < <(find "${MODULE_ROOT}/scripts" "${MODULE_ROOT}/tests" -type f -name '*.sh' | sort)
for f in "${SCRIPTS[@]}"; do
  bash -n "${f}" && pass "bash -n $(basename "${f}")" || fail "bash -n $(basename "${f}")"
done
if command -v shellcheck >/dev/null 2>&1; then
  for f in "${SCRIPTS[@]}"; do
    shellcheck -x --severity=warning -e SC1091 "${f}" >/tmp/kyverno-lab-shellcheck.$$ 2>&1 \
      && pass "shellcheck $(basename "${f}")" \
      || { fail "shellcheck $(basename "${f}")"; cat /tmp/kyverno-lab-shellcheck.$$; }
  done
  rm -f /tmp/kyverno-lab-shellcheck.$$
else
  skip "shellcheck not installed — only bash -n syntax checks ran."
fi

log_section "2. YAML structural validation"
if command -v python3 >/dev/null 2>&1; then
  mapfile -t YAML_FILES < <(find "${MODULE_ROOT}/install" "${MODULE_ROOT}/demo" "${MODULE_ROOT}/policies" "${MODULE_ROOT}/tests/cli-test-cases" -type f -name '*.yaml' | sort)
  YAML_FAIL=0
  for f in "${YAML_FILES[@]}"; do
    if ! python3 -c "
import sys, yaml
list(yaml.safe_load_all(open('${f}')))
" 2>/tmp/kyverno-lab-yaml-err.$$; then
      fail "YAML parse: ${f#"${MODULE_ROOT}"/}"
      cat /tmp/kyverno-lab-yaml-err.$$
      YAML_FAIL=1
    fi
  done
  rm -f /tmp/kyverno-lab-yaml-err.$$
  [ "${YAML_FAIL}" -eq 0 ] && pass "All ${#YAML_FILES[@]} YAML files parse."
else
  skip "python3 not installed — skipped YAML structural validation."
fi

log_section "3. Helm values syntax and helm lint"
if command -v helm >/dev/null 2>&1; then
  for values in "${MODULE_ROOT}/install/values-minimum.yaml" "${MODULE_ROOT}/install/values-recommended.yaml"; do
    if helm repo list 2>/dev/null | grep -q "^${KYVERNO_HELM_REPO_NAME}"; then :; else
      helm repo add "${KYVERNO_HELM_REPO_NAME}" "${KYVERNO_CHART_REPO}" >/dev/null 2>&1 || true
    fi
    if helm lint "${KYVERNO_HELM_REPO_NAME}/kyverno" --version "${KYVERNO_CHART_VERSION}" --values "${values}" >/tmp/kyverno-lab-helmlint.$$ 2>&1; then
      pass "helm lint $(basename "${values}")"
    else
      warn "helm lint $(basename "${values}") reported issues (or the chart repo isn't reachable from this host):"
      cat /tmp/kyverno-lab-helmlint.$$
    fi
    rm -f /tmp/kyverno-lab-helmlint.$$
  done
else
  skip "helm not installed — skipped helm lint. YAML structural validation (step 2) still covers basic syntax."
fi

log_section "4. Kyverno CLI offline policy tests"
if command -v kyverno >/dev/null 2>&1; then
  if kyverno test "${MODULE_ROOT}/tests/cli-test-cases/"; then
    pass "kyverno test tests/cli-test-cases/"
  else
    fail "kyverno test tests/cli-test-cases/ reported failures."
  fi
  log_info "Unsupported-offline cases (documented, not silently skipped): generate-rule and PolicyException CLI test coverage is best-effort depending on installed CLI version; verifyImages rules are syntax-checked only — no real signature/registry network call happens offline. See tests/expected-results.md."
else
  skip "Kyverno CLI ('kyverno') not installed — offline policy tests (step 4) skipped entirely. See labs/lab-00-prerequisites.md."
fi

log_section "5. Policy quality checks (kyverno.io API version, duplicate names, description/message presence)"
mapfile -t POLICY_FILES < <(find "${MODULE_ROOT}/policies" -type f -name '*.yaml' | sort)
DUPLICATE_CHECK_FILE="$(mktemp)"
for f in "${POLICY_FILES[@]}"; do
  API_VERSION="$(grep -m1 '^apiVersion:' "${f}" | awk '{print $2}')"
  case "${API_VERSION}" in
    kyverno.io/v1|kyverno.io/v2) pass "$(basename "${f}"): current API version (${API_VERSION})" ;;
    kyverno.io/v1beta1|kyverno.io/v2beta1) warn "$(basename "${f}"): uses a beta API version (${API_VERSION}) — verify this is still accepted by chart ${KYVERNO_CHART_VERSION}." ;;
    *) warn "$(basename "${f}"): unexpected/missing apiVersion (${API_VERSION:-<none>})" ;;
  esac

  NAME="$(grep -m1 '^  name:' "${f}" | awk '{print $2}')"
  echo "${NAME}" >>"${DUPLICATE_CHECK_FILE}"

  if grep -q 'policies.kyverno.io/description' "${f}"; then
    pass "$(basename "${f}"): has a description annotation"
  else
    fail "$(basename "${f}"): missing policies.kyverno.io/description annotation"
  fi

  if grep -q 'message:' "${f}"; then
    pass "$(basename "${f}"): has at least one validation message"
  else
    warn "$(basename "${f}"): no 'message:' field found (fine for pure mutate/generate-only policies, otherwise check)"
  fi
done

DUPLICATES="$(sort "${DUPLICATE_CHECK_FILE}" | uniq -d)"
rm -f "${DUPLICATE_CHECK_FILE}"
if [ -n "${DUPLICATES}" ]; then
  fail "Duplicate policy name(s) found: ${DUPLICATES}"
else
  pass "No duplicate policy names across policies/."
fi

log_section "6. Unsafe wildcard / namespace-exclusion checks"
for f in "${POLICY_FILES[@]}"; do
  if grep -qE 'kinds:\s*\[\s*"\*"\s*\]' "${f}"; then
    fail "$(basename "${f}"): matches kinds: [\"*\"] — unsafely broad, narrow the match."
  fi
done
pass "No policy matches all kinds via a bare wildcard."

log_section "7. Image tag hygiene in policy/demo YAML (excluding intentionally-insecure fixtures)"
LATEST_TAG_HITS=0
while IFS= read -r f; do
  if grep -q 'lab-marker: intentionally-insecure' "${f}"; then
    continue
  fi
  if grep -qE 'image:\s*[^ ]+:latest' "${f}"; then
    warn "$(basename "${f}"): references a ':latest' image tag outside an intentionally-insecure fixture."
    LATEST_TAG_HITS=$((LATEST_TAG_HITS + 1))
  fi
done < <(find "${MODULE_ROOT}/demo" "${MODULE_ROOT}/install" -type f -name '*.yaml')
[ "${LATEST_TAG_HITS}" -eq 0 ] && pass "No unexpected ':latest' image tags outside intentionally-insecure fixtures."

log_section "8. Markdown link check (this module only)"
if command -v python3 >/dev/null 2>&1; then
  python3 - "${MODULE_ROOT}" <<'PYEOF'
import re, os, sys
root = sys.argv[1]
files = []
for r, d, fs in os.walk(root):
    for f in fs:
        if f.endswith(".md"):
            files.append(os.path.join(r, f))
link_re = re.compile(r'\]\(([a-zA-Z0-9_./-]+\.md[^)]*)\)')
broken = []
checked = 0
for f in files:
    base_dir = os.path.dirname(f)
    with open(f, errors="replace") as fh:
        content = fh.read()
    for m in link_re.finditer(content):
        path = m.group(1).split('#')[0]
        resolved = os.path.normpath(os.path.join(base_dir, path))
        checked += 1
        if not os.path.isfile(resolved):
            broken.append((f, m.group(1)))
print(f"[INFO] Checked {checked} relative .md links across {len(files)} files in kyverno/.")
if broken:
    for f, link in broken:
        print(f"[FAIL] {f} -> {link}")
    sys.exit(1)
print("[PASS] All relative markdown links in kyverno/ resolve.")
PYEOF
  [ "$?" -eq 0 ] || fail "Markdown link check found broken links."
else
  skip "python3 not installed — skipped markdown link check."
fi

log_section "9. Makefile help"
if (cd "${MODULE_ROOT}" && make help >/tmp/kyverno-lab-makehelp.$$ 2>&1); then
  TARGET_COUNT="$(grep -c '^  [a-z]' /tmp/kyverno-lab-makehelp.$$ || true)"
  pass "make help succeeded, listing ${TARGET_COUNT} targets."
else
  fail "make help failed."
fi
rm -f /tmp/kyverno-lab-makehelp.$$

echo
if [ "${FAIL}" -ne 0 ]; then
  log_fail "static-validation: one or more mandatory checks failed."
  exit 1
fi
log_pass "static-validation: all mandatory checks passed."
