#!/usr/bin/env bash
# Guest provisioning step 06: install Cilium (CNI + eBPF datapath) and
# Hubble via Helm, plus the Cilium CLI and Hubble CLI for validation.
# Runs only on the control plane. Idempotent via `helm upgrade --install`.
# Requires Helm (09-install-helm.sh) to have already run — see Vagrantfile
# for actual execution order.
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
  log_info "06-install-cilium: not the control plane, skipping (${NODE_NAME})."
  exit 0
fi

log_section "06-install-cilium: Cilium ${CILIUM_CHART_VERSION} + Hubble (${NODE_NAME})"

require_cmd helm
export KUBECONFIG=/etc/kubernetes/admin.conf
export CONTROL_PLANE_IP CILIUM_CLUSTER_POOL_CIDR CILIUM_CLUSTER_POOL_MASK_SIZE
export HUBBLE_UI_ENABLED="${HUBBLE_UI_ENABLED:-true}"

render_template "${MODULE_ROOT}/config/cilium-values.yaml.tpl" "${RENDERED_DIR}/cilium-values.yaml"

helm repo add cilium "${CILIUM_HELM_REPO}" >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

helm upgrade --install cilium cilium/cilium \
  --version "${CILIUM_CHART_VERSION}" \
  --namespace "${CILIUM_NAMESPACE}" \
  --values "${RENDERED_DIR}/cilium-values.yaml" \
  --wait --timeout 5m
log_pass "Cilium chart ${CILIUM_CHART_VERSION} applied (helm upgrade --install)."

# --- Cilium CLI (for `cilium status`/`cilium connectivity test`) --------
CILIUM_CLI_VERSION_OUTPUT="$(cilium version --client 2>/dev/null || true)"
if ! command -v cilium >/dev/null 2>&1 || ! grep -q "${CILIUM_CLI_VERSION}" <<<"${CILIUM_CLI_VERSION_OUTPUT}"; then
  ARCH="$(dpkg --print-architecture)"
  WORKDIR="$(mktemp -d)"
  trap 'rm -rf "${WORKDIR}"' EXIT
  CLI_TARBALL="cilium-linux-${ARCH}.tar.gz"
  BASE_URL="https://github.com/cilium/cilium-cli/releases/download/v${CILIUM_CLI_VERSION}"
  curl -fsSL "${BASE_URL}/${CLI_TARBALL}" -o "${WORKDIR}/${CLI_TARBALL}"
  curl -fsSL "${BASE_URL}/${CLI_TARBALL}.sha256sum" -o "${WORKDIR}/${CLI_TARBALL}.sha256sum"
  (cd "${WORKDIR}" && sha256sum -c "${CLI_TARBALL}.sha256sum")
  tar -xzf "${WORKDIR}/${CLI_TARBALL}" -C /usr/local/bin cilium
  log_pass "Cilium CLI v${CILIUM_CLI_VERSION} installed (checksum verified)."
else
  log_info "Cilium CLI already at v${CILIUM_CLI_VERSION}, skipping."
fi

# --- Hubble CLI (matches the installed Cilium minor line) ---------------
HUBBLE_CLI_VERSION="$(curl -fsSL https://raw.githubusercontent.com/cilium/hubble/master/stable.txt 2>/dev/null || true)"
if [ -z "${HUBBLE_CLI_VERSION}" ]; then
  log_warn "Could not resolve Hubble CLI 'stable' version dynamically; skipping Hubble CLI install (Hubble Relay/UI are still installed and reachable via kubectl port-forward)."
elif ! command -v hubble >/dev/null 2>&1; then
  ARCH="$(dpkg --print-architecture)"
  WORKDIR2="$(mktemp -d)"
  trap 'rm -rf "${WORKDIR2}"' EXIT
  HUBBLE_TARBALL="hubble-linux-${ARCH}.tar.gz"
  BASE_URL2="https://github.com/cilium/hubble/releases/download/${HUBBLE_CLI_VERSION}"
  curl -fsSL "${BASE_URL2}/${HUBBLE_TARBALL}" -o "${WORKDIR2}/${HUBBLE_TARBALL}"
  curl -fsSL "${BASE_URL2}/${HUBBLE_TARBALL}.sha256sum" -o "${WORKDIR2}/${HUBBLE_TARBALL}.sha256sum"
  (cd "${WORKDIR2}" && sha256sum -c "${HUBBLE_TARBALL}.sha256sum")
  tar -xzf "${WORKDIR2}/${HUBBLE_TARBALL}" -C /usr/local/bin hubble
  log_pass "Hubble CLI ${HUBBLE_CLI_VERSION} installed (checksum verified)."
fi

# --- Wait for Cilium/Hubble readiness ------------------------------------
wait_for "Cilium DaemonSet rollout" 180 5 -- \
  bash -c "kubectl -n ${CILIUM_NAMESPACE} rollout status daemonset/cilium --timeout=5s"
wait_for "Cilium operator rollout" 120 5 -- \
  bash -c "kubectl -n ${CILIUM_NAMESPACE} rollout status deployment/cilium-operator --timeout=5s"
wait_for "Hubble Relay rollout" 120 5 -- \
  bash -c "kubectl -n ${CILIUM_NAMESPACE} rollout status deployment/hubble-relay --timeout=5s"

if command -v cilium >/dev/null 2>&1; then
  cilium status --wait || log_warn "'cilium status --wait' reported issues — inspect before continuing (see docs/TROUBLESHOOTING.md)."
fi
if command -v hubble >/dev/null 2>&1; then
  kubectl -n "${CILIUM_NAMESPACE}" port-forward deployment/hubble-relay 4245:4245 >/tmp/hubble-port-forward.log 2>&1 &
  HUBBLE_PF_PID=$!
  sleep 3
  HUBBLE_ADDRESS=localhost:4245 hubble status || log_warn "'hubble status' via temporary port-forward reported issues."
  kill "${HUBBLE_PF_PID}" 2>/dev/null || true
fi

log_info "Access: kubectl -n ${CILIUM_NAMESPACE} port-forward deployment/hubble-ui 12000:80  (see docs/CILIUM-HUBBLE.md for UI/CLI access instructions)"
log_pass "06-install-cilium complete for ${NODE_NAME}."
