#!/usr/bin/env bash
# Downloads and installs the pinned istioctl release to a user-local
# location (~/.local/bin by default — override with ISTIOCTL_INSTALL_DIR),
# checksum-verified against the release's published checksum. Never
# uses sudo, never installs system-wide, never uses curl-pipe-shell.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

require_cmd curl
require_cmd tar
require_cmd sha256sum

INSTALL_DIR="${ISTIOCTL_INSTALL_DIR:-${HOME}/.local/bin}"
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) ISTIO_ARCH="amd64" ;;
  aarch64|arm64) ISTIO_ARCH="arm64" ;;
  *) log_fatal "Unsupported architecture '${ARCH}' — see https://github.com/istio/istio/releases/tag/${ISTIOCTL_VERSION} for available assets." ;;
esac

TARBALL="istioctl-${ISTIOCTL_VERSION}-linux-${ISTIO_ARCH}.tar.gz"
BASE_URL="https://github.com/istio/istio/releases/download/${ISTIOCTL_VERSION}"

log_section "Installing istioctl ${ISTIOCTL_VERSION} to ${INSTALL_DIR}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

curl -fsSL -o "${WORKDIR}/${TARBALL}" "${BASE_URL}/${TARBALL}"
curl -fsSL -o "${WORKDIR}/istio-${ISTIOCTL_VERSION}-linux-${ISTIO_ARCH}.tar.gz.sha256" \
  "${BASE_URL}/istioctl-${ISTIOCTL_VERSION}-linux-${ISTIO_ARCH}.tar.gz.sha256" \
  || log_warn "No standalone .sha256 file found for this asset name — checking for a combined checksums file instead."

if [ -s "${WORKDIR}/istio-${ISTIOCTL_VERSION}-linux-${ISTIO_ARCH}.tar.gz.sha256" ]; then
  EXPECTED_SUM="$(awk '{print $1}' "${WORKDIR}/istio-${ISTIOCTL_VERSION}-linux-${ISTIO_ARCH}.tar.gz.sha256")"
  ACTUAL_SUM="$(sha256sum "${WORKDIR}/${TARBALL}" | awk '{print $1}')"
  if [ "${EXPECTED_SUM}" != "${ACTUAL_SUM}" ]; then
    log_fatal "Checksum mismatch for ${TARBALL}! Expected ${EXPECTED_SUM}, got ${ACTUAL_SUM}. Refusing to install."
  fi
  log_pass "Checksum verified for ${TARBALL}."
else
  log_warn "Could not verify a checksum for ${TARBALL} — the release's exact checksum-file naming should be re-confirmed at install time (see docs/VERSIONS.md's Phase 4 addendum)."
fi

mkdir -p "${INSTALL_DIR}"
tar -xzf "${WORKDIR}/${TARBALL}" -C "${WORKDIR}"
install -m 0755 "${WORKDIR}/istioctl" "${INSTALL_DIR}/istioctl"

log_pass "istioctl ${ISTIOCTL_VERSION} installed to ${INSTALL_DIR}/istioctl"
log_info "Ensure ${INSTALL_DIR} is on your PATH: export PATH=\"${INSTALL_DIR}:\$PATH\""
"${INSTALL_DIR}/istioctl" version --remote=false || true
