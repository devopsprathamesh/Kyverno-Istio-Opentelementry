# opentelemetry-prometheus-grafana-jaeger-loki/ — Makefile
#
# Default target is `help`; it makes no changes. This module never
# invokes Vagrant, never resets Kubernetes, never modifies Cilium, and
# never installs Kyverno or Istio. Every install/runtime target
# requires `verify-cluster` to pass first.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
MODULE_ROOT := $(shell cd "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))" && pwd)

LAB_PROFILE ?= recommended
VALID_PROFILES := minimum recommended

.PHONY: help prerequisites verify-cluster \
        install-prometheus install-grafana install-jaeger install-loki install-operator install-collector install-all build-demo-images \
        validate-prometheus validate-grafana validate-jaeger validate-loki validate-operator validate-collector validate-installation \
        deploy-demo generate-load inject-latency inject-errors \
        test-prometheus test-grafana test-jaeger test-loki test-traces test-metrics test-logs test-correlation test-sampling test-resilience test-static test-runtime validate \
        status collector-status port-forward-prometheus port-forward-grafana port-forward-jaeger port-forward-loki port-forward-demo debug-bundle \
        clean-demo clean-collector clean-backends clean \
        uninstall-prometheus uninstall-grafana uninstall-jaeger uninstall-loki uninstall-operator uninstall-collector uninstall-all \
        _check-profile

help: ## Show this help (default target; makes no changes)
	@echo "opentelemetry-prometheus-grafana-jaeger-loki — independent observability lab"
	@echo
	@echo "Usage: make <target> [LAB_PROFILE=minimum|recommended]"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN{FS=":.*## "}{printf "  %-26s %s\n", $$1, $$2}'

_check-profile:
	@if ! echo " $(VALID_PROFILES) " | grep -q " $(LAB_PROFILE) "; then \
		echo "[FAIL] Invalid LAB_PROFILE='$(LAB_PROFILE)'. Valid values: $(VALID_PROFILES)"; \
		exit 1; \
	fi

prerequisites: ## Check required CLI tools (kubectl, helm, python3, docker/podman, vagrant) — read-only
	@"$(MODULE_ROOT)/scripts/check-prerequisites.sh"

verify-cluster: ## Confirm cluster identity + Cilium/kube-proxy/CoreDNS/storage health
	@"$(MODULE_ROOT)/scripts/verify-cluster.sh"

## --- Install -----------------------------------------------------------

install-operator: _check-profile verify-cluster ## Install the OpenTelemetry Operator (CRDs + webhook, Helm self-signed certs)
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install-operator.sh"

install-prometheus: _check-profile verify-cluster ## Install kube-prometheus-stack (Prometheus + Operator + Alertmanager + kube-state-metrics + node-exporter)
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install-prometheus.sh"

install-jaeger: _check-profile verify-cluster ## Install Jaeger v2 (official Helm chart, not the deprecated Operator)
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install-jaeger.sh"

install-loki: _check-profile verify-cluster ## Install Loki (Monolithic mode, native OTLP ingestion)
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install-loki.sh"

install-collector: _check-profile verify-cluster ## Install the Collector Agent DaemonSet + Gateway Deployment (raw manifests)
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install-collector.sh"

install-grafana: _check-profile verify-cluster ## Install Grafana with Prometheus/Jaeger/Loki datasources + dashboards provisioned
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install-grafana.sh"

install-all: _check-profile verify-cluster ## Install the full stack in dependency order (Operator -> Prometheus -> Jaeger -> Loki -> Collector -> Grafana)
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install-all.sh"

build-demo-images: ## Build the 5 demo-application images locally and import them into every cluster node's containerd (no registry)
	@"$(MODULE_ROOT)/scripts/build-demo-images.sh"

## --- Validate ------------------------------------------------------------

validate-operator: verify-cluster ## Validate Operator CRDs/webhook/Deployment
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" operator

validate-prometheus: verify-cluster ## Validate Prometheus pod/query-API/targets/rules
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" prometheus

validate-grafana: verify-cluster ## Validate Grafana health + datasource health + dashboard provisioning
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" grafana

validate-jaeger: verify-cluster ## Validate Jaeger Query UI + OTLP ingestion + a test trace
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" jaeger

validate-loki: verify-cluster ## Validate Loki readiness + OTLP log ingestion
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" loki

validate-collector: verify-cluster ## Validate Collector Agent/Gateway health + internal metrics
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" collector

validate-installation: verify-cluster ## Run every component validation, in order (operator, prometheus, jaeger, loki, collector, grafana, e2e)
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" all

## --- Demo application ------------------------------------------------------

deploy-demo: verify-cluster ## Deploy the demo microservices app (requires build-demo-images to have run first)
	@"$(MODULE_ROOT)/scripts/deploy-demo.sh"

generate-load: verify-cluster ## Generate load against the demo app. Args: make generate-load ARGS="200 10 60"
	@"$(MODULE_ROOT)/scripts/generate-load.sh" $(ARGS)

inject-latency: verify-cluster ## Inject configurable latency into payment-service. Args: make inject-latency ARGS="1500 apply"
	@"$(MODULE_ROOT)/scripts/inject-latency.sh" $(ARGS)

inject-errors: verify-cluster ## Inject configurable failure rate into payment-service. Args: make inject-errors ARGS="30 apply"
	@"$(MODULE_ROOT)/scripts/inject-errors.sh" $(ARGS)

## --- Test ------------------------------------------------------------------

test-prometheus: verify-cluster ## Runtime test: Prometheus
	@bash "$(MODULE_ROOT)/tests/prometheus-test.sh"

test-grafana: verify-cluster ## Runtime test: Grafana
	@bash "$(MODULE_ROOT)/tests/grafana-test.sh"

test-jaeger: verify-cluster ## Runtime test: Jaeger
	@bash "$(MODULE_ROOT)/tests/jaeger-test.sh"

test-loki: verify-cluster ## Runtime test: Loki
	@bash "$(MODULE_ROOT)/tests/loki-test.sh"

test-traces: verify-cluster ## Runtime test: end-to-end trace delivery
	@bash "$(MODULE_ROOT)/tests/traces-test.sh"

test-metrics: verify-cluster ## Runtime test: end-to-end metrics delivery
	@bash "$(MODULE_ROOT)/tests/metrics-test.sh"

test-logs: verify-cluster ## Runtime test: end-to-end log delivery (filelog path)
	@bash "$(MODULE_ROOT)/tests/logs-test.sh"

test-correlation: verify-cluster ## Runtime test: trace-log correlation and metric exemplars
	@bash "$(MODULE_ROOT)/tests/correlation-test.sh"

test-sampling: verify-cluster ## Runtime test: tail-sampling policies (errors/slow traces always kept)
	@bash "$(MODULE_ROOT)/tests/sampling-test.sh"

test-resilience: verify-cluster ## Runtime test: backend-outage/queue/backpressure behavior
	@bash "$(MODULE_ROOT)/tests/resilience-test.sh"

test-static: ## Offline validation: shell/YAML/JSON syntax, Collector config sanity, Dockerfile review (no cluster required)
	@bash "$(MODULE_ROOT)/tests/static-validation.sh"

test-runtime: verify-cluster ## Full runtime test suite against a live cluster
	@for t in prometheus-test grafana-test jaeger-test loki-test collector-test traces-test metrics-test logs-test correlation-test sampling-test resilience-test; do \
		echo "==> tests/$$t.sh"; \
		bash "$(MODULE_ROOT)/tests/$$t.sh" || exit 1; \
	done

validate: verify-cluster ## Full end-to-end runtime validation (alias for validate-installation scope=all)
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" all

## --- Status / access ---------------------------------------------------

status: ## Quick read-only status glance across all 3 namespaces
	@"$(MODULE_ROOT)/scripts/status.sh"

collector-status: verify-cluster ## Collector-specific status (internal metrics, health)
	@"$(MODULE_ROOT)/scripts/validate-installation.sh" collector

port-forward-prometheus: verify-cluster ## localhost:9090 -> Prometheus
	@"$(MODULE_ROOT)/scripts/port-forward.sh" prometheus

port-forward-grafana: verify-cluster ## localhost:3000 -> Grafana
	@"$(MODULE_ROOT)/scripts/port-forward.sh" grafana

port-forward-jaeger: verify-cluster ## localhost:16686 -> Jaeger Query UI
	@"$(MODULE_ROOT)/scripts/port-forward.sh" jaeger

port-forward-loki: verify-cluster ## localhost:3100 -> Loki
	@"$(MODULE_ROOT)/scripts/port-forward.sh" loki

port-forward-demo: verify-cluster ## localhost:8080 -> demo app frontend
	@"$(MODULE_ROOT)/scripts/port-forward.sh" demo

debug-bundle: verify-cluster ## Collect a sanitized troubleshooting bundle under .generated/debug-bundles/
	@"$(MODULE_ROOT)/scripts/collect-debug-bundle.sh"

## --- Cleanup / uninstall -------------------------------------------------

clean-demo: verify-cluster ## Remove the demo application and any temporary lab namespaces (backends untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" demo

clean-collector: verify-cluster ## Remove the Collector Agent/Gateway manifests (Helm releases untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" collector

clean-backends: verify-cluster ## Remove lab-applied Prometheus rule/monitor objects (Helm-managed resources untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" backends

clean: verify-cluster ## Remove demo app + Collector manifests + lab-applied rule/monitor objects (Helm releases untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" all

uninstall-prometheus: verify-cluster ## DESTRUCTIVE: remove the kube-prometheus-stack Helm release
	@REMOVE_CRDS="$(REMOVE_CRDS)" "$(MODULE_ROOT)/scripts/uninstall-all.sh" prometheus

uninstall-grafana: verify-cluster ## DESTRUCTIVE: remove the Grafana Helm release
	@"$(MODULE_ROOT)/scripts/uninstall-all.sh" grafana

uninstall-jaeger: verify-cluster ## DESTRUCTIVE: remove the Jaeger Helm release
	@"$(MODULE_ROOT)/scripts/uninstall-all.sh" jaeger

uninstall-loki: verify-cluster ## DESTRUCTIVE: remove the Loki Helm release
	@"$(MODULE_ROOT)/scripts/uninstall-all.sh" loki

uninstall-operator: verify-cluster ## DESTRUCTIVE: remove the OpenTelemetry Operator Helm release
	@REMOVE_CRDS="$(REMOVE_CRDS)" "$(MODULE_ROOT)/scripts/uninstall-all.sh" operator

uninstall-collector: verify-cluster ## DESTRUCTIVE: remove the Collector Agent/Gateway manifests + RBAC
	@"$(MODULE_ROOT)/scripts/uninstall-all.sh" collector

uninstall-all: verify-cluster ## DESTRUCTIVE: remove every Helm release + the Collector's raw manifests (CRDs kept unless REMOVE_CRDS=true)
	@REMOVE_CRDS="$(REMOVE_CRDS)" "$(MODULE_ROOT)/scripts/uninstall-all.sh" all
