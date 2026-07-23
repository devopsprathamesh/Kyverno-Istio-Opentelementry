#!/usr/bin/env bash
# Guest provisioning step 09 (filename order only — see Vagrantfile for
# actual execution order, which runs this BEFORE 05/06 because Cilium is
# installed via Helm): install the pinned Helm release on the
# control-plane VM via a checksum-verified tarball download rather than
# a curl-pipe-shell install script. Runs only on the control plane —
# workers never need a local Helm binary. Idempotent.
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
: "${NODE_NAME:?}"
: "${NODE_ROLE:?}"

if [ "${NODE_ROLE}" != "control-plane" ]; then
  log_info "09-install-helm: not the control plane, skipping (${NODE_NAME})."
  exit 0
fi

log_section "09-install-helm: Helm ${HELM_VERSION} (${NODE_NAME})"

HELM_VERSION_OUTPUT="$(helm version --template '{{.Version}}' 2>/dev/null || true)"
if command -v helm >/dev/null 2>&1 && grep -q "v${HELM_VERSION}" <<<"${HELM_VERSION_OUTPUT}"; then
  log_info "Helm ${HELM_VERSION} already installed, skipping."
else
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "${WORKDIR}"' EXIT
  TARBALL="helm-v${HELM_VERSION}-linux-amd64.tar.gz"
  curl -fsSL "https://get.helm.sh/${TARBALL}" -o "${WORKDIR}/${TARBALL}"
  curl -fsSL "https://get.helm.sh/${TARBALL}.sha256sum" -o "${WORKDIR}/${TARBALL}.sha256sum"
  (cd "${WORKDIR}" && sha256sum -c "${TARBALL}.sha256sum")
  tar -xzf "${WORKDIR}/${TARBALL}" -C "${WORKDIR}"
  install -m 0755 "${WORKDIR}/linux-amd64/helm" /usr/local/bin/helm
  log_pass "Helm v${HELM_VERSION} installed to /usr/local/bin/helm (checksum verified)."
fi

log_info "Validation: helm version -> $(helm version --short 2>/dev/null || true)"
log_pass "09-install-helm complete for ${NODE_NAME}."
