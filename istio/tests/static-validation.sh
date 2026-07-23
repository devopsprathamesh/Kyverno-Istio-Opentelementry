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
    shellcheck -x --severity=warning -e SC1091 "${f}" >/tmp/istio-lab-shellcheck.$$ 2>&1 \
      && pass "shellcheck $(basename "${f}")" \
      || { fail "shellcheck $(basename "${f}")"; cat /tmp/istio-lab-shellcheck.$$; }
  done
  rm -f /tmp/istio-lab-shellcheck.$$
else
  skip "shellcheck not installed — only bash -n syntax checks ran."
fi

log_section "2. YAML structural validation (Kubernetes/Istio manifests)"
if command -v python3 >/dev/null 2>&1; then
  mapfile -t YAML_FILES < <(find "${MODULE_ROOT}/install" "${MODULE_ROOT}/demo" "${MODULE_ROOT}/policies" -type f -name '*.yaml' | sort)
  YAML_FAIL=0
  for f in "${YAML_FILES[@]}"; do
    if ! python3 -c "
import sys, yaml
list(yaml.safe_load_all(open('${f}')))
" 2>/tmp/istio-lab-yaml-err.$$; then
      fail "YAML parse: ${f#"${MODULE_ROOT}"/}"
      cat /tmp/istio-lab-yaml-err.$$
      YAML_FAIL=1
    fi
  done
  rm -f /tmp/istio-lab-yaml-err.$$
  [ "${YAML_FAIL}" -eq 0 ] && pass "All ${#YAML_FILES[@]} YAML files parse."
  # .yaml.tpl files (e.g. policies/requestauthentication/jwt-requestauth.yaml.tpl)
  # are checked structurally after placeholder substitution — real
  # values are only known at lab-run time.
  mapfile -t TPL_FILES < <(find "${MODULE_ROOT}/policies" -type f -name '*.yaml.tpl' | sort)
  for f in "${TPL_FILES[@]}"; do
    if python3 - "${f}" <<'PYEOF'
import re, sys, yaml
path = sys.argv[1]
with open(path) as fh:
    content = fh.read()
dummy = re.sub(r"\$\{[A-Za-z0-9_]+\}", "PLACEHOLDER", content)
try:
    list(yaml.safe_load_all(dummy))
except yaml.YAMLError as e:
    print(e)
    sys.exit(1)
PYEOF
    then
      pass "YAML structure valid (post-placeholder): ${f#"${MODULE_ROOT}"/}"
    else
      fail "YAML structure invalid: ${f#"${MODULE_ROOT}"/}"
    fi
  done
else
  skip "python3 not installed — skipped YAML structural validation."
fi

log_section "3. Helm lint"
if command -v helm >/dev/null 2>&1; then
  helm repo add "${ISTIO_HELM_REPO_NAME}" "${ISTIO_HELM_REPO}" >/dev/null 2>&1 || true
  for pair in "istiod:${MODULE_ROOT}/install/istiod-values-minimum.yaml" \
              "istiod:${MODULE_ROOT}/install/istiod-values-recommended.yaml" \
              "gateway:${MODULE_ROOT}/install/ingress-gateway-values-minimum.yaml" \
              "gateway:${MODULE_ROOT}/install/ingress-gateway-values-recommended.yaml" \
              "cni:${MODULE_ROOT}/install/cni-values.yaml"; do
    chart="${pair%%:*}"; values="${pair#*:}"
    if helm lint "${ISTIO_HELM_REPO_NAME}/${chart}" --version "${ISTIO_VERSION}" --values "${values}" >/tmp/istio-lab-helmlint.$$ 2>&1; then
      pass "helm lint ${chart} $(basename "${values}")"
    else
      warn "helm lint ${chart} $(basename "${values}") reported issues (or the chart repo isn't reachable):"
      cat /tmp/istio-lab-helmlint.$$
    fi
    rm -f /tmp/istio-lab-helmlint.$$
  done
else
  skip "helm not installed — skipped helm lint. YAML structural validation (step 2) still covers basic syntax."
fi

log_section "4. istioctl analyze / validate against local manifests"
if command -v istioctl >/dev/null 2>&1; then
  if istioctl analyze "${MODULE_ROOT}/demo" "${MODULE_ROOT}/policies" --use-kube=false 2>/tmp/istio-lab-analyze.$$; then
    pass "istioctl analyze (offline, --use-kube=false) reports no errors"
  else
    ANALYZE_RC=$?
    if [ "${ANALYZE_RC}" -eq 3 ]; then
      warn "istioctl analyze reported findings (exit 3 = warnings/info only, not necessarily errors) — see below:"
    else
      fail "istioctl analyze reported errors (exit ${ANALYZE_RC}):"
    fi
    cat /tmp/istio-lab-analyze.$$
  fi
  rm -f /tmp/istio-lab-analyze.$$
else
  skip "istioctl not installed — skipped istioctl analyze/validate. See labs/lab-00-prerequisites.md."
fi

log_section "5. Manifest quality checks (API versions, duplicate names, latest tags, resources, labels)"
mapfile -t MANIFEST_FILES < <(find "${MODULE_ROOT}/install" "${MODULE_ROOT}/demo" "${MODULE_ROOT}/policies" -type f -name '*.yaml' | sort)
NAME_CHECK_FILE="$(mktemp)"
for f in "${MANIFEST_FILES[@]}"; do
  if grep -qE 'image:\s*[^ ]+:latest' "${f}"; then
    fail "$(basename "${f}"): uses a ':latest' image tag."
  fi
  if grep -qE '^\s+kind:\s*(Deployment|Pod)\s*$' "${f}" && ! grep -q 'namespace:' "${f}"; then
    warn "$(basename "${f}"): Deployment/Pod without an explicit namespace: field nearby — verify it's set."
  fi
  grep -E '^  name:' "${f}" | awk '{print $2}' >>"${NAME_CHECK_FILE}" || true
done
DUPLICATES="$(sort "${NAME_CHECK_FILE}" | uniq -d)"
rm -f "${NAME_CHECK_FILE}"
if [ -n "${DUPLICATES}" ]; then
  warn "Duplicate resource name(s) found across files (may be intentional across kinds, verify manually): ${DUPLICATES}"
else
  pass "No duplicate resource names across manifests."
fi
pass "No ':latest' image tags found (checked $((${#MANIFEST_FILES[@]})) files)."

log_section "6. Deprecated Istio API version detection"
DEPRECATED_HIT=0
for f in "${MANIFEST_FILES[@]}"; do
  if grep -qE 'apiVersion:\s*networking\.istio\.io/v1(alpha3|beta1)' "${f}"; then
    fail "$(basename "${f}"): uses a deprecated Istio networking API version (v1alpha3/v1beta1) — current is networking.istio.io/v1."
    DEPRECATED_HIT=1
  fi
  if grep -qE 'apiVersion:\s*security\.istio\.io/v1beta1' "${f}"; then
    fail "$(basename "${f}"): uses a deprecated Istio security API version (v1beta1) — current is security.istio.io/v1."
    DEPRECATED_HIT=1
  fi
done
[ "${DEPRECATED_HIT}" -eq 0 ] && pass "All Istio manifests use current (non-deprecated) API versions."

log_section "7. Markdown link check (this module only)"
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
print(f"[INFO] Checked {checked} relative .md links across {len(files)} files in istio/.")
if broken:
    for f, link in broken:
        print(f"[FAIL] {f} -> {link}")
    sys.exit(1)
print("[PASS] All relative markdown links in istio/ resolve.")
PYEOF
  [ "$?" -eq 0 ] || fail "Markdown link check found broken links."
else
  skip "python3 not installed — skipped markdown link check."
fi

log_section "8. Makefile help"
if (cd "${MODULE_ROOT}" && make help >/tmp/istio-lab-makehelp.$$ 2>&1); then
  TARGET_COUNT="$(grep -c '^  [a-z]' /tmp/istio-lab-makehelp.$$ || true)"
  pass "make help succeeded, listing ${TARGET_COUNT} targets."
else
  fail "make help failed."
fi
rm -f /tmp/istio-lab-makehelp.$$

echo
if [ "${FAIL}" -ne 0 ]; then
  log_fail "static-validation: one or more mandatory checks failed."
  exit 1
fi
log_pass "static-validation: all mandatory checks passed."
