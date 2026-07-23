#!/usr/bin/env bash
# Static check: Vagrantfile syntax/config validity and config/ template
# structure. Never creates or modifies VMs.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${MODULE_ROOT}"

FAIL=0

if command -v ruby >/dev/null 2>&1; then
  echo "==> ruby -c Vagrantfile"
  if ruby -c Vagrantfile; then
    echo "[PASS] Vagrantfile is syntactically valid Ruby"
  else
    echo "[FAIL] Vagrantfile has a Ruby syntax error"
    FAIL=1
  fi
else
  echo "[WARN] ruby not installed on this host — skipped 'ruby -c Vagrantfile' syntax check."
fi

if command -v vagrant >/dev/null 2>&1; then
  echo "==> vagrant validate"
  if vagrant validate; then
    echo "[PASS] 'vagrant validate' accepted the Vagrantfile"
  else
    echo "[FAIL] 'vagrant validate' rejected the Vagrantfile"
    FAIL=1
  fi
else
  echo "[WARN] vagrant not installed on this host — skipped 'vagrant validate'."
fi

echo "==> YAML template structural checks (config/*.yaml.tpl)"
if command -v python3 >/dev/null 2>&1; then
  for tpl in config/*.yaml.tpl; do
    # Templates contain ${VAR} placeholders that are not valid YAML
    # scalars on their own in every position, so we substitute dummy
    # values before parsing purely for *structural* (indentation/
    # document-separator) validity, not semantic correctness.
    python3 - "${tpl}" <<'PYEOF'
import re, sys, yaml
path = sys.argv[1]
with open(path) as f:
    content = f.read()
dummy = re.sub(r"\$\{[A-Za-z0-9_]+\}", "PLACEHOLDER", content)
try:
    list(yaml.safe_load_all(dummy))
    print(f"[PASS] YAML structure valid (post-placeholder-substitution): {path}")
except yaml.YAMLError as e:
    print(f"[FAIL] YAML structure invalid: {path}\n{e}")
    sys.exit(1)
PYEOF
  done
else
  echo "[WARN] python3 not installed — skipped YAML template structural checks."
fi

exit "${FAIL}"
