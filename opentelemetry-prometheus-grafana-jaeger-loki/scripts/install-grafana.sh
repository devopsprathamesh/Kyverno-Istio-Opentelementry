#!/usr/bin/env bash
# Installs Grafana via the grafana-community Helm chart, with Prometheus/
# Jaeger/Loki data sources and dashboards provisioned automatically.
# Generates a random admin password into .generated/ (git-ignored) —
# never a hardcoded or committed credential. Installed LAST among the
# backends so its data-source health checks have something to check
# against on first install.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl
require_cmd helm

PROFILE="$(profile_arg)"
VALUES_FILE="${MODULE_ROOT}/install/grafana/values-${PROFILE}.yaml"
[ -f "${VALUES_FILE}" ] || log_fatal "Values file not found: ${VALUES_FILE}"

log_section "Installing Grafana ${GRAFANA_APP_VERSION}, profile=${PROFILE}"

kubectl apply -f "${MODULE_ROOT}/install/namespaces/"

ensure_generated_dir
PASSWORD_FILE="${GENERATED_DIR}/grafana-admin-password"
if [ ! -f "${PASSWORD_FILE}" ]; then
  python3 -c 'import secrets,string; print("".join(secrets.choice(string.ascii_letters+string.digits) for _ in range(24)))' >"${PASSWORD_FILE}"
  chmod 600 "${PASSWORD_FILE}"
  log_pass "Generated a random Grafana admin password into ${PASSWORD_FILE} (git-ignored, never committed)."
else
  log_info "Reusing existing generated admin password at ${PASSWORD_FILE}."
fi
GRAFANA_ADMIN_PASSWORD="$(cat "${PASSWORD_FILE}")"

helm repo add "${GRAFANA_HELM_REPO_NAME}" "${GRAFANA_HELM_REPO}" >/dev/null 2>&1 || true
helm repo update "${GRAFANA_HELM_REPO_NAME}" >/dev/null

DATASOURCES_FILE="${MODULE_ROOT}/install/grafana/datasources/datasources.yaml"
[ -f "${DATASOURCES_FILE}" ] || log_fatal "Datasources file not found: ${DATASOURCES_FILE}"

helm upgrade --install grafana "${GRAFANA_HELM_REPO_NAME}/grafana" \
  --version "${GRAFANA_HELM_CHART_VERSION}" \
  --namespace "${OBSERVABILITY_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --values "${DATASOURCES_FILE}" \
  --set image.tag="${GRAFANA_APP_VERSION#v}" \
  --set adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
  --wait --timeout "${HELM_TIMEOUT}"

log_info "Provisioning dashboards from grafana/dashboards/..."
kubectl create configmap grafana-dashboards-provisioning \
  --namespace "${OBSERVABILITY_NAMESPACE}" \
  --from-file="${MODULE_ROOT}/grafana/dashboards/" \
  --dry-run=client -o yaml | kubectl label -f - --local -o yaml grafana_dashboard=1 \
  | kubectl apply -f -

log_pass "Grafana applied. Admin user '${GRAFANA_LAB_DEFAULT_USER}', password stored at ${PASSWORD_FILE} (run: cat ${PASSWORD_FILE})."
log_pass "Grafana installation complete. Run 'make validate-grafana' next."
