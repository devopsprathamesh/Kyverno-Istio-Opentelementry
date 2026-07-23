#!/usr/bin/env bash
# Shared logging helpers. Source this file, never execute it directly.
#
# Consistent log levels across every script in this module:
#   [INFO] narration of what is about to happen
#   [PASS] a check succeeded
#   [WARN] a non-fatal problem or a below-recommended condition
#   [FAIL] a fatal problem — callers should treat this as an error signal
#
# log_fail() does not exit by itself (some callers want to collect
# multiple failures before deciding whether to abort); it increments
# LOG_FAIL_COUNT so callers can check it and exit non-zero themselves.

set -euo pipefail

LOG_FAIL_COUNT="${LOG_FAIL_COUNT:-0}"
LOG_WARN_COUNT="${LOG_WARN_COUNT:-0}"

_log_ts() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_pass() {
  printf '[PASS] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
  LOG_WARN_COUNT=$((LOG_WARN_COUNT + 1))
}

log_fail() {
  printf '[FAIL] %s\n' "$*" >&2
  LOG_FAIL_COUNT=$((LOG_FAIL_COUNT + 1))
}

# log_fatal: like log_fail, but exits immediately. Use for errors that
# make continuing pointless (missing required command, unreadable config).
log_fatal() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

log_section() {
  printf '\n==> %s\n' "$*"
}
