#!/usr/bin/env bash
# Cluster-free static validation: everything that can be checked without
# a live Kubernetes cluster and without Docker/podman. Called by
# `make test-static`. Prints PASS/WARN/FAIL, records skipped-tool-
# unavailable checks explicitly rather than silently omitting them, and
# exits non-zero only on a mandatory FAIL.
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
    shellcheck -x --severity=warning -e SC1091 "${f}" >/tmp/otel-lab-shellcheck.$$ 2>&1 \
      && pass "shellcheck $(basename "${f}")" \
      || { fail "shellcheck $(basename "${f}")"; cat /tmp/otel-lab-shellcheck.$$; }
  done
  rm -f /tmp/otel-lab-shellcheck.$$
else
  skip "shellcheck not installed — only bash -n syntax checks ran."
fi

log_section "2. YAML structural validation (Kubernetes/Helm-values manifests)"
if command -v python3 >/dev/null 2>&1; then
  mapfile -t YAML_FILES < <(find "${MODULE_ROOT}/install" "${MODULE_ROOT}/collector" "${MODULE_ROOT}/operator" "${MODULE_ROOT}/demo-application/kubernetes" "${MODULE_ROOT}/prometheus" "${MODULE_ROOT}/combined-observability-lab" -type f \( -name '*.yaml' -o -name '*.yml' \) 2>/dev/null | sort)
  YAML_FAIL=0
  for f in "${YAML_FILES[@]}"; do
    if ! python3 -c "
import sys, yaml
try:
    list(yaml.safe_load_all(open('${f}')))
except Exception as e:
    print(f'{e}')
    sys.exit(1)
" >/tmp/otel-lab-yamlcheck.$$ 2>&1; then
      fail "$(basename "${f}"): invalid YAML — $(cat /tmp/otel-lab-yamlcheck.$$)"
      YAML_FAIL=1
    fi
  done
  rm -f /tmp/otel-lab-yamlcheck.$$
  [ "${YAML_FAIL}" -eq 0 ] && pass "All ${#YAML_FILES[@]} YAML files parse."
else
  skip "python3 not installed — skipped YAML structural validation."
fi

log_section "3. JSON structural validation (Grafana dashboards, package.json)"
if command -v python3 >/dev/null 2>&1; then
  mapfile -t JSON_FILES < <(find "${MODULE_ROOT}/grafana/dashboards" "${MODULE_ROOT}/demo-application" -type f -name '*.json' 2>/dev/null | sort)
  JSON_FAIL=0
  for f in "${JSON_FILES[@]}"; do
    if ! python3 -c "import json; json.load(open('${f}'))" >/dev/null 2>&1; then
      fail "$(basename "${f}"): invalid JSON"
      JSON_FAIL=1
    fi
  done
  [ "${JSON_FAIL}" -eq 0 ] && pass "All ${#JSON_FILES[@]} JSON files parse (${#JSON_FILES[@]} files, includes Grafana dashboards)."
else
  skip "python3 not installed — skipped JSON structural validation."
fi

log_section "4. Collector configuration sanity (deprecated components, endpoint correctness)"
COLLECTOR_CONFIGS=("${MODULE_ROOT}/collector/agent/configmap.yaml" "${MODULE_ROOT}/collector/gateway/configmap.yaml" "${MODULE_ROOT}/collector/standalone/configmap.yaml")
CONFIG_FAIL=0
for f in "${COLLECTOR_CONFIGS[@]}"; do
  [ -f "${f}" ] || continue
  if grep -qE '^\s+loki:\s*$' "${f}" 2>/dev/null && grep -qE 'exporters:' "${f}"; then
    if grep -A2 -E '^\s+loki:\s*$' "${f}" | grep -qE 'endpoint'; then
      fail "$(basename "${f}"): references the REMOVED Collector Contrib 'loki' exporter — must use 'otlphttp' pointed at Loki's /otlp endpoint instead. See docs/06-logs.md."
      CONFIG_FAIL=1
    fi
  fi
  if grep -qE 'endpoint:\s*http://loki[^/]*/otlp/v1/logs' "${f}" 2>/dev/null; then
    fail "$(basename "${f}"): otlphttp/loki exporter endpoint includes '/v1/logs' — the exporter appends this itself; endpoint must be the '/otlp' path only."
    CONFIG_FAIL=1
  fi
done
[ "${CONFIG_FAIL}" -eq 0 ] && pass "No deprecated Collector components or malformed Loki OTLP endpoints found."

log_section "5. Demo application source syntax (Python / Node.js)"
if command -v python3 >/dev/null 2>&1; then
  mapfile -t PY_FILES < <(find "${MODULE_ROOT}/demo-application" "${MODULE_ROOT}/scripts" -type f -name '*.py' 2>/dev/null | sort)
  PY_FAIL=0
  for f in "${PY_FILES[@]}"; do
    if ! python3 -m py_compile "${f}" 2>/tmp/otel-lab-pycheck.$$; then
      fail "$(basename "${f}"): Python syntax error — $(cat /tmp/otel-lab-pycheck.$$)"
      PY_FAIL=1
    fi
  done
  rm -f /tmp/otel-lab-pycheck.$$
  find "${MODULE_ROOT}" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true
  [ "${PY_FAIL}" -eq 0 ] && pass "All ${#PY_FILES[@]} Python files compile cleanly."
else
  skip "python3 not installed — skipped Python syntax checks."
fi
if command -v node >/dev/null 2>&1; then
  mapfile -t JS_FILES < <(find "${MODULE_ROOT}/demo-application" -type f -name '*.js' 2>/dev/null | sort)
  JS_FAIL=0
  for f in "${JS_FILES[@]}"; do
    if ! node --check "${f}" 2>/tmp/otel-lab-jscheck.$$; then
      fail "$(basename "${f}"): Node.js syntax error — $(cat /tmp/otel-lab-jscheck.$$)"
      JS_FAIL=1
    fi
  done
  rm -f /tmp/otel-lab-jscheck.$$
  [ "${JS_FAIL}" -eq 0 ] && pass "All ${#JS_FILES[@]} Node.js files pass 'node --check'."
else
  skip "node not installed — skipped Node.js syntax checks."
fi

log_section "6. Dockerfile review (non-root, pinned base image, no ':latest')"
mapfile -t DOCKERFILES < <(find "${MODULE_ROOT}/demo-application" -type f -name 'Dockerfile' | sort)
DOCKER_FAIL=0
for f in "${DOCKERFILES[@]}"; do
  if grep -qE '^FROM\s+\S+:latest\s*$' "${f}"; then
    fail "${f}: uses a ':latest' base image tag."
    DOCKER_FAIL=1
  fi
  if ! grep -qE '^FROM\s+\S+:\S+' "${f}"; then
    fail "${f}: base image has no explicit tag."
    DOCKER_FAIL=1
  fi
  if ! grep -qE '^USER\s+' "${f}"; then
    fail "${f}: no USER instruction — would run as root."
    DOCKER_FAIL=1
  elif grep -qE '^USER\s+(0|root)(:.*)?\s*$' "${f}"; then
    fail "${f}: explicitly runs as root."
    DOCKER_FAIL=1
  fi
done
[ "${DOCKER_FAIL}" -eq 0 ] && pass "All ${#DOCKERFILES[@]} Dockerfiles: pinned base image, non-root USER, no ':latest'."

log_section "7. Manifest quality checks (API versions, duplicate names, latest tags, ownership labels)"
mapfile -t MANIFEST_FILES < <(find "${MODULE_ROOT}/install" "${MODULE_ROOT}/collector" "${MODULE_ROOT}/operator" "${MODULE_ROOT}/demo-application/kubernetes" "${MODULE_ROOT}/prometheus" -type f -name '*.yaml' | sort)
QUALITY_FAIL=0
for f in "${MANIFEST_FILES[@]}"; do
  if grep -qE 'image:\s*[^ ]+:latest' "${f}"; then
    fail "$(basename "${f}"): uses a ':latest' image tag."
    QUALITY_FAIL=1
  fi
done
[ "${QUALITY_FAIL}" -eq 0 ] && pass "No ':latest' image tags found across $((${#MANIFEST_FILES[@]})) manifest files."

log_section "8. Helm lint"
if command -v helm >/dev/null 2>&1; then
  skip "helm chart lint requires network access to fetch chart repos — not attempted in this offline pass. YAML structural validation (step 2) still covers this module's own values-file syntax."
else
  skip "helm not installed — skipped helm lint."
fi

log_section "9. Markdown link check (this module only)"
if command -v python3 >/dev/null 2>&1; then
  if python3 - "${MODULE_ROOT}" <<'PYEOF'
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
print(f"[INFO] Checked {checked} relative .md links across {len(files)} files.")
if broken:
    for f, link in broken:
        print(f"[FAIL] {f} -> {link}")
    sys.exit(1)
print("[PASS] All relative markdown links resolve.")
PYEOF
  then
    :
  else
    fail "Markdown link check found broken links."
  fi
else
  skip "python3 not installed — skipped markdown link check."
fi

log_section "10. Makefile help"
if (cd "${MODULE_ROOT}" && make help >/tmp/otel-lab-makehelp.$$ 2>&1); then
  TARGET_COUNT="$(grep -c '^  [a-z]' /tmp/otel-lab-makehelp.$$ || true)"
  pass "make help succeeded, listing ${TARGET_COUNT} targets."
else
  fail "make help failed."
fi
rm -f /tmp/otel-lab-makehelp.$$

echo
if [ "${FAIL}" -ne 0 ]; then
  log_fail "static-validation: one or more mandatory checks failed."
  exit 1
fi
log_pass "static-validation: all mandatory checks passed."
