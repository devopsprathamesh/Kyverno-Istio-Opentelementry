#!/usr/bin/env bash
# Shared logging helpers. Source this file, never execute it directly.
# Deliberately self-contained (not shared with auto-setup-default-kube-env)
# per this repository's cross-module reuse rule: independent labs must
# not reference each other's files (docs/REPOSITORY-GOVERNANCE.md).
#
#   [INFO] narration of what is about to happen
#   [PASS] a check succeeded
#   [WARN] a non-fatal problem or below-recommended condition
#   [FAIL] a fatal problem — callers should treat this as an error signal
set -euo pipefail

LOG_FAIL_COUNT="${LOG_FAIL_COUNT:-0}"
LOG_WARN_COUNT="${LOG_WARN_COUNT:-0}"

_log_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

log_info() { printf '[INFO] %s\n' "$*"; }
log_pass() { printf '[PASS] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; LOG_WARN_COUNT=$((LOG_WARN_COUNT + 1)); }
log_fail() { printf '[FAIL] %s\n' "$*" >&2; LOG_FAIL_COUNT=$((LOG_FAIL_COUNT + 1)); }
log_fatal() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
log_section() { printf '\n==> %s\n' "$*"; }
