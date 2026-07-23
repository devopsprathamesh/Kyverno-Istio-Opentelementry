#!/usr/bin/env bash
# Guest provisioning step 03: install and configure containerd as the
# CRI runtime. containerd's own project does not publish an apt
# repository; the Docker apt repository's `containerd.io` package is the
# documented, trusted distribution channel used here. Idempotent.
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
: "${NODE_NAME:?}"

log_section "03-install-containerd: containerd ${CONTAINERD_VERSION} (${NODE_NAME})"

CONTAINERD_VERSION_OUTPUT="$(containerd --version 2>/dev/null || true)"
if ! is_containerd_active || ! grep -q "${CONTAINERD_VERSION}" <<<"${CONTAINERD_VERSION_OUTPUT}"; then
  export DEBIAN_FRONTEND=noninteractive
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi
  ARCH="$(dpkg --print-architecture)"
  UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -y

  # Exact Docker-repo package revision suffix (the "-1" here) can shift
  # between Ubuntu codenames; verify against `apt-cache madison containerd.io`
  # at install time per docs/VERSIONS.md's re-check-at-install-time pattern.
  CONTAINERD_PKG_CANDIDATE="$(apt-cache madison containerd.io | awk -v v="${CONTAINERD_VERSION}" '$3 ~ v {print $3; exit}')"
  if [ -z "${CONTAINERD_PKG_CANDIDATE}" ]; then
    log_fatal "No containerd.io package matching version ${CONTAINERD_VERSION} found via apt-cache madison. Re-check config/versions.env against the Docker apt repo."
  fi
  apt-get install -y --no-install-recommends "containerd.io=${CONTAINERD_PKG_CANDIDATE}"
  apt-mark hold containerd.io
  log_pass "containerd.io ${CONTAINERD_PKG_CANDIDATE} installed and held."
else
  log_info "containerd ${CONTAINERD_VERSION} already active, skipping install."
fi

# --- Generate the authoritative default config with the installed binary
# itself, then patch only the keys documented in
# config/containerd-config.toml.tpl, rather than hand-authoring a full
# config against containerd 2.x's restructured CRI-plugin schema.
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml

if grep -q 'io.containerd.cri.v1.runtime' /etc/containerd/config.toml; then
  RUNTIME_PLUGIN='io.containerd.cri.v1.runtime'
  IMAGES_PLUGIN='io.containerd.cri.v1.images'
else
  RUNTIME_PLUGIN='io.containerd.grpc.v1.cri'
  IMAGES_PLUGIN='io.containerd.grpc.v1.cri'
fi
log_info "Detected CRI plugin namespace: ${RUNTIME_PLUGIN}"

python3 - "$RUNTIME_PLUGIN" "$IMAGES_PLUGIN" <<'PYEOF'
import re, sys
runtime_plugin, images_plugin = sys.argv[1], sys.argv[2]
path = "/etc/containerd/config.toml"
with open(path) as f:
    content = f.read()

# SystemdCgroup = true under the runc runtime options block.
content = re.sub(
    r'(\[plugins\."%s"\.containerd\.runtimes\.runc\.options\][^\[]*?SystemdCgroup\s*=\s*)false'
    % re.escape(runtime_plugin),
    r"\1true",
    content,
)
# sandbox_image pin, under the images plugin block.
content = re.sub(
    r'(\[plugins\."%s"\][^\[]*?sandbox_image\s*=\s*)"[^"]*"' % re.escape(images_plugin),
    r'\1"registry.k8s.io/pause:3.10"',
    content,
)
with open(path, "w") as f:
    f.write(content)
PYEOF

if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  log_warn "SystemdCgroup=true patch did not apply as expected — inspect /etc/containerd/config.toml manually."
fi

cp "${MODULE_ROOT}/config/crictl.yaml" /etc/crictl.yaml

systemctl enable --now containerd
systemctl restart containerd
wait_for "containerd active" 30 2 -- is_containerd_active

log_info "Validation: containerd --version -> $(containerd --version)"
log_info "Validation: crictl info -> $(crictl --runtime-endpoint "${CRI_SOCKET}" info >/dev/null 2>&1 && echo OK || echo FAILED)"
log_info "Validation: crictl version -> $(crictl --runtime-endpoint "${CRI_SOCKET}" version 2>/dev/null || true)"

cp /etc/containerd/config.toml "${RENDERED_DIR}/containerd-config-${NODE_NAME}.toml" 2>/dev/null || true

log_pass "03-install-containerd complete for ${NODE_NAME}. Flow: kubelet -> CRI (${CRI_SOCKET}) -> containerd -> runc."
