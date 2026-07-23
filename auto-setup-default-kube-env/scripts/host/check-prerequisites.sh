#!/usr/bin/env bash
# Host-side prerequisite validation. Read-only: never installs software,
# never unloads kernel modules, never disables host services. Prints
# PASS/WARN/FAIL and exits non-zero only when a FAIL was recorded (a
# missing prerequisite that would actually prevent environment creation).
#
# Usage: scripts/host/check-prerequisites.sh [LAB_PROFILE]
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_not_root
LAB_PROFILE="${1:-${LAB_PROFILE:-${DEFAULT_LAB_PROFILE}}}"

log_section "Host prerequisite check (profile: ${LAB_PROFILE})"

FAIL_COUNT=0
pass() { log_pass "$1"; }
warn() { log_warn "$1"; }
fail() { log_fail "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# --- Operating system -----------------------------------------------------
UNAME_S="$(uname -s)"
if [ "${UNAME_S}" = "Linux" ] || [ "${UNAME_S}" = "Darwin" ]; then
  pass "Host OS is ${UNAME_S} ($(uname -r 2>/dev/null || true))"
else
  warn "Host OS '${UNAME_S}' is not Linux/macOS — this module is only validated on those."
fi

# --- Required commands ------------------------------------------------
for cmd in git make curl ssh VBoxManage vagrant; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    pass "'${cmd}' is installed ($("${cmd}" --version 2>/dev/null | head -1))"
  else
    fail "'${cmd}' is not installed or not on PATH."
  fi
done

# --- CPU virtualization support ------------------------------------------
if [ "${UNAME_S}" = "Linux" ]; then
  VMX_SVM_COUNT="$(grep -Ec '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo 0)"
  if [ "${VMX_SVM_COUNT}" -gt 0 ]; then
    pass "Hardware virtualization detected (${VMX_SVM_COUNT} cpuflag matches for vmx/svm)."
  else
    fail "No hardware virtualization support detected in /proc/cpuinfo (vmx/svm)."
  fi

  # --- KVM/VirtualBox coexistence note -----------------------------------
  # Output is captured before matching (not piped straight into `grep -q`)
  # to avoid a SIGPIPE-under-`pipefail` false negative: grep -q exits as
  # soon as it finds a match, which can close the pipe while lsmod is
  # still writing its remaining output, making the pipeline's exit status
  # reflect lsmod's SIGPIPE kill instead of grep's real (successful) match.
  LOADED_MODULES="$(lsmod 2>/dev/null)"
  if grep -qi '^kvm' <<<"${LOADED_MODULES}"; then
    warn "KVM kernel modules are loaded; VirtualBox 7.x can normally coexist with KVM loaded, but if VM boot fails with a virtualization error, that's the first thing to check (see docs/TROUBLESHOOTING.md). This script does NOT unload KVM modules automatically."
  else
    pass "No KVM kernel modules loaded (no potential VirtualBox/KVM coexistence question)."
  fi
else
  warn "CPU virtualization flag check skipped (not Linux)."
fi

# --- VirtualBox provider sanity --------------------------------------
if command -v VBoxManage >/dev/null 2>&1; then
  if VBoxManage list vms >/dev/null 2>&1; then
    pass "VBoxManage is executable and responsive."
  else
    fail "VBoxManage is installed but did not respond to 'VBoxManage list vms' — check VirtualBox installation/kernel driver."
  fi
fi

# --- Available system RAM -------------------------------------------------
if [ "${UNAME_S}" = "Linux" ] && command -v free >/dev/null 2>&1; then
  AVAILABLE_MB="$(free -m | awk '/^Mem:/{print $7}')"
  case "${LAB_PROFILE}" in
    minimum) REQUIRED_MB="${MINIMUM_PROFILE_TOTAL_MEMORY_MB}" ;;
    recommended) REQUIRED_MB="${RECOMMENDED_PROFILE_TOTAL_MEMORY_MB}" ;;
    *) fail "Unknown LAB_PROFILE '${LAB_PROFILE}' (expected one of: ${VALID_LAB_PROFILES})"; REQUIRED_MB=0 ;;
  esac
  if [ "${REQUIRED_MB}" -gt 0 ]; then
    if [ "${AVAILABLE_MB}" -ge "${REQUIRED_MB}" ]; then
      pass "Available memory (${AVAILABLE_MB}MB) meets the '${LAB_PROFILE}' profile requirement (${REQUIRED_MB}MB)."
    else
      fail "Available memory (${AVAILABLE_MB}MB) is below the '${LAB_PROFILE}' profile requirement (${REQUIRED_MB}MB)."
    fi
  fi
else
  warn "Could not determine available RAM on this OS; verify manually that you have enough for the '${LAB_PROFILE}' profile."
fi

# --- Available disk space -------------------------------------------------
AVAILABLE_DISK_KB="$(df -Pk "${HOME}" | tail -1 | awk '{print $4}')"
REQUIRED_DISK_KB=$((40 * 1024 * 1024)) # ~40GB: 3 VM disks + box cache + image layers
if [ "${AVAILABLE_DISK_KB}" -ge "${REQUIRED_DISK_KB}" ]; then
  pass "Available disk space ($((AVAILABLE_DISK_KB / 1024 / 1024))GB) is comfortably above the ~40GB guideline."
else
  warn "Available disk space ($((AVAILABLE_DISK_KB / 1024 / 1024))GB) is below the ~40GB guideline — 3 VM disks plus box/image caches may not fit."
fi

# --- vagrant-disksize plugin (needed if box disk resize is ever used) ---
INSTALLED_PLUGINS="$(vagrant plugin list 2>/dev/null)"
if grep -q vagrant-disksize <<<"${INSTALLED_PLUGINS}"; then
  pass "vagrant-disksize plugin is installed."
else
  warn "vagrant-disksize plugin not installed — only relevant if you later resize VM disks beyond the box default; not required for default setup."
fi

# --- Existing Vagrant/VirtualBox state -----------------------------------
EXISTING_VMS="$(VBoxManage list vms 2>/dev/null || true)"
log_info "Existing VirtualBox VMs on this host:"
echo "${EXISTING_VMS}"
log_info "Existing Vagrant environments known to this host:"
vagrant global-status 2>/dev/null || true

for name in "${CONTROL_PLANE_NAME}" "${WORKER1_NAME}" "${WORKER2_NAME}"; do
  if grep -q "\"${name}\"" <<<"${EXISTING_VMS}"; then
    warn "A VirtualBox VM named '${name}' already exists — 'vagrant up' will reuse/manage it, but if it belongs to an unrelated environment this is a naming collision. Investigate before proceeding."
  fi
done

# --- Conflicting private network range -----------------------------------
log_info "Existing VirtualBox host-only interfaces:"
VBoxManage list hostonlyifs 2>/dev/null | grep -E '^(Name|IPAddress):' || true

CONFLICT_FOUND=0
for ip in "${CONTROL_PLANE_IP}" "${WORKER1_IP}" "${WORKER2_IP}"; do
  if command -v ping >/dev/null 2>&1 && ping -c1 -W1 "${ip}" >/dev/null 2>&1; then
    warn "Something is already answering on ${ip} — this overlaps with this module's planned static IP. If it's an unrelated VM/host, resolve the conflict (power it off, or see docs/TROUBLESHOOTING.md 'Host-only IP conflict') before running 'make setup'."
    CONFLICT_FOUND=1
  fi
done
if [ "${CONFLICT_FOUND}" -eq 0 ]; then
  pass "No host currently answers on ${CONTROL_PLANE_IP}, ${WORKER1_IP}, or ${WORKER2_IP} — target IPs look free."
fi

# --- Required local ports (Vagrant's NAT SSH forwarding range) ----------
if command -v ss >/dev/null 2>&1; then
  BUSY_PORTS="$(ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | grep -oE '[0-9]+$' | awk '$1>=2200 && $1<=2250' | tr '\n' ' ')"
  if [ -n "${BUSY_PORTS}" ]; then
    warn "Some ports in Vagrant's typical SSH-forward range (2200-2250) are already in use: ${BUSY_PORTS}. Vagrant will pick free ports automatically; this is informational only."
  else
    pass "Vagrant's typical SSH-forward port range (2200-2250) looks free."
  fi
fi

echo
if [ "${FAIL_COUNT}" -gt 0 ]; then
  log_fail "Prerequisite check failed: ${FAIL_COUNT} mandatory check(s) did not pass."
  exit 1
fi
log_pass "All mandatory prerequisite checks passed for profile '${LAB_PROFILE}'."
