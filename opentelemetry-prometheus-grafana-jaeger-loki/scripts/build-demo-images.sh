#!/usr/bin/env bash
# Builds the demo application's 5 images locally (docker or podman) and
# imports them directly into every cluster node's containerd via
# `vagrant ssh <node> -- sudo ctr -n k8s.io images import -` — no
# registry, public or private, is ever used. See
# docs/DECISIONS.md ADR-030 and docs/labs/lab-00-prerequisites.md.
#
# Requires: a container builder (docker or podman) on this host, and
# vagrant ssh access to the base platform's VMs (../auto-setup-default-
# kube-env). Both are checked by check-prerequisites.sh; this script
# re-checks and fails clearly rather than partially building.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"

BUILDER=""
if command -v docker >/dev/null 2>&1; then
  BUILDER="docker"
elif command -v podman >/dev/null 2>&1; then
  BUILDER="podman"
else
  log_fatal "Neither docker nor podman found. This step cannot run on this host — see labs/lab-00-prerequisites.md. Every other part of this module (install, docs, labs) does not require a container builder."
fi
log_info "Using builder: ${BUILDER}"

BASE_PLATFORM_DIR="$(cd "${MODULE_ROOT}/../auto-setup-default-kube-env" && pwd)"
if ! command -v vagrant >/dev/null 2>&1; then
  log_fatal "vagrant not found — cannot import built images into cluster nodes' containerd without vagrant ssh access. See ${BASE_PLATFORM_DIR}/README.md."
fi

declare -A IMAGES=(
  [frontend]="${DEMO_FRONTEND_IMAGE}:${DEMO_FRONTEND_IMAGE_TAG}"
  [order-service]="${DEMO_ORDER_SERVICE_IMAGE}:${DEMO_ORDER_SERVICE_IMAGE_TAG}"
  [inventory-service]="${DEMO_INVENTORY_SERVICE_IMAGE}:${DEMO_INVENTORY_SERVICE_IMAGE_TAG}"
  [payment-service]="${DEMO_PAYMENT_SERVICE_IMAGE}:${DEMO_PAYMENT_SERVICE_IMAGE_TAG}"
  [load-generator]="${DEMO_LOAD_GENERATOR_IMAGE}:${DEMO_LOAD_GENERATOR_IMAGE_TAG}"
)

ensure_generated_dir
TARBALL_DIR="${GENERATED_DIR}/demo-images"
mkdir -p "${TARBALL_DIR}"

log_section "Building ${#IMAGES[@]} demo application images"
for svc in "${!IMAGES[@]}"; do
  tag="${IMAGES[${svc}]}"
  log_info "Building ${tag} from demo-application/${svc}/Dockerfile ..."
  "${BUILDER}" build -t "${tag}" -f "${MODULE_ROOT}/demo-application/${svc}/Dockerfile" "${MODULE_ROOT}/demo-application/${svc}"
  log_pass "Built ${tag}"
  "${BUILDER}" save "${tag}" -o "${TARBALL_DIR}/${svc}.tar"
done

log_section "Importing images into every cluster node's containerd"
for node in "${EXPECTED_CONTROL_PLANE_NAME}" "${EXPECTED_WORKER1_NAME}" "${EXPECTED_WORKER2_NAME}"; do
  for svc in "${!IMAGES[@]}"; do
    log_info "Importing ${svc} into ${node}..."
    (cd "${BASE_PLATFORM_DIR}" && vagrant ssh "${node}" -c "sudo ctr -n k8s.io images import -" < "${TARBALL_DIR}/${svc}.tar")
  done
  log_pass "All images imported into ${node}."
done

log_pass "build-demo-images complete. Kubernetes manifests use imagePullPolicy: Never and reference these exact tags — see demo-application/kubernetes/."
