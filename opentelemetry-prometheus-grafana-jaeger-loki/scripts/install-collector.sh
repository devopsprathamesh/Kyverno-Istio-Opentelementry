#!/usr/bin/env bash
# Installs the OpenTelemetry Collector as raw Kubernetes manifests (RBAC
# + ConfigMap + DaemonSet agent, RBAC + ConfigMap + Deployment gateway)
# rather than an Operator-managed OpenTelemetryCollector CRD — gives
# full control over hostPath mounts, RBAC, and the agent/gateway split.
# See docs/DECISIONS.md ADR-029. Requires Prometheus/Jaeger/Loki to
# already be installed so the Gateway's exporters have real Services to
# reference (the Gateway will still start and queue/retry if a backend
# isn't ready yet, but install-all.sh orders this after the backends
# for a clean first-run experience).
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=./lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

require_cmd kubectl

PROFILE="$(profile_arg)"
log_section "Installing OpenTelemetry Collector (agent DaemonSet + gateway Deployment), image ${OTEL_COLLECTOR_CONTRIB_VERSION}, profile=${PROFILE}"

kubectl apply -f "${MODULE_ROOT}/install/namespaces/"

log_info "Step 1/2: Collector Gateway (Deployment) — must exist first so the Agent's exporter has a Service to target"
kubectl apply -f "${MODULE_ROOT}/collector/gateway/serviceaccount.yaml"
kubectl apply -f "${MODULE_ROOT}/collector/gateway/clusterrole.yaml"
kubectl apply -f "${MODULE_ROOT}/collector/gateway/clusterrolebinding.yaml"
kubectl apply -f "${MODULE_ROOT}/collector/gateway/configmap.yaml"
sed "s/__REPLICA_COUNT__/$( [ "${PROFILE}" = recommended ] && echo 2 || echo 1 )/;s#__IMAGE__#${OTEL_COLLECTOR_CONTRIB_IMAGE}:${OTEL_COLLECTOR_CONTRIB_VERSION}#" \
  "${MODULE_ROOT}/collector/gateway/deployment.yaml" | kubectl apply -f -
kubectl apply -f "${MODULE_ROOT}/collector/gateway/service.yaml"
wait_for "Collector Gateway rollout" "${INSTALL_WAIT_TIMEOUT_SECONDS}" 5 -- \
  deployment_rollout_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-gateway "${INSTALL_WAIT_TIMEOUT_SECONDS}"

log_info "Step 2/2: Collector Agent (DaemonSet, one per node)"
kubectl apply -f "${MODULE_ROOT}/collector/agent/serviceaccount.yaml"
kubectl apply -f "${MODULE_ROOT}/collector/agent/clusterrole.yaml"
kubectl apply -f "${MODULE_ROOT}/collector/agent/clusterrolebinding.yaml"
kubectl apply -f "${MODULE_ROOT}/collector/agent/configmap.yaml"
sed "s#__IMAGE__#${OTEL_COLLECTOR_CONTRIB_IMAGE}:${OTEL_COLLECTOR_CONTRIB_VERSION}#" \
  "${MODULE_ROOT}/collector/agent/daemonset.yaml" | kubectl apply -f -
wait_for "Collector Agent DaemonSet Ready on all nodes" "${INSTALL_WAIT_TIMEOUT_SECONDS}" 5 -- \
  daemonset_ready "${OPENTELEMETRY_NAMESPACE}" otel-collector-agent

log_info "Applying the Gateway's PodMonitor so Prometheus scrapes Collector internal metrics..."
kubectl apply -f "${MODULE_ROOT}/prometheus/podmonitors/" 2>/dev/null || true

log_pass "OpenTelemetry Collector installation complete. Run 'make validate-collector' next."
