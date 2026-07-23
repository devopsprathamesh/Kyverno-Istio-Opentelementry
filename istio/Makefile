# istio/ — Makefile
#
# Default target is `help`; it makes no changes. This module never
# invokes Vagrant, never resets Kubernetes, never modifies Cilium, and
# never installs observability tooling — every install/runtime target
# requires `verify-cluster` to pass first, confirming this is the
# intended local learning cluster with healthy Cilium/kube-proxy/CoreDNS.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
MODULE_ROOT := $(shell cd "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))" && pwd)

LAB_PROFILE ?= recommended
VALID_PROFILES := minimum recommended

.PHONY: help prerequisites verify-cluster install-istioctl install install-minimum \
        install-recommended validate-installation deploy-demo enable-injection \
        disable-injection generate-traffic inject-latency inject-errors test \
        test-static test-runtime status proxy-status proxy-config analyze \
        debug-bundle clean-demo clean-config clean uninstall _check-profile

help: ## Show this help (default target; makes no changes)
	@echo "istio — independent Istio hands-on lab"
	@echo
	@echo "Usage: make <target> [LAB_PROFILE=minimum|recommended]"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN{FS=":.*## "}{printf "  %-22s %s\n", $$1, $$2}'

_check-profile:
	@if ! echo " $(VALID_PROFILES) " | grep -q " $(LAB_PROFILE) "; then \
		echo "[FAIL] Invalid LAB_PROFILE='$(LAB_PROFILE)'. Valid values: $(VALID_PROFILES)"; \
		exit 1; \
	fi

prerequisites: ## Check required CLI tools (kubectl, helm, istioctl) — read-only
	@"$(MODULE_ROOT)/scripts/check-prerequisites.sh"

verify-cluster: ## Confirm cluster identity + Cilium/kube-proxy/CoreDNS health + CNI-chaining compat
	@"$(MODULE_ROOT)/scripts/verify-cluster.sh"

install-istioctl: ## Download and install the pinned istioctl to ~/.local/bin (checksum-verified)
	@"$(MODULE_ROOT)/scripts/install-istioctl.sh"

install: _check-profile verify-cluster ## Install Istio (base -> istiod -> istio-cni -> gateway), LAB_PROFILE=minimum|recommended
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install.sh"

install-minimum: ## Shortcut for 'make install LAB_PROFILE=minimum'
	@$(MAKE) --no-print-directory install LAB_PROFILE=minimum

install-recommended: ## Shortcut for 'make install LAB_PROFILE=recommended'
	@$(MAKE) --no-print-directory install LAB_PROFILE=recommended

validate-installation: verify-cluster ## Validate control plane, CNI, gateway, webhooks, sidecar injection, proxy sync
	@"$(MODULE_ROOT)/scripts/validate-installation.sh"

deploy-demo: verify-cluster ## Deploy the demo microservices app + ingress Gateway to istio-demo
	@"$(MODULE_ROOT)/scripts/deploy-demo.sh"

enable-injection: verify-cluster ## Label istio-demo for automatic sidecar injection (restores the default state)
	@kubectl label namespace istio-demo "istio.io/rev=$$(grep ISTIO_REVISION config/lab-settings.env | cut -d= -f2)" --overwrite

disable-injection: verify-cluster ## Remove sidecar-injection labels from istio-demo (used by lab-19 'missing-sidecar' scenario)
	@"$(MODULE_ROOT)/scripts/inject-failures.sh" missing-sidecar apply

generate-traffic: verify-cluster ## Generate a controlled burst of HTTP requests (see scripts/generate-traffic.sh for args)
	@"$(MODULE_ROOT)/scripts/generate-traffic.sh"

inject-latency: verify-cluster ## Apply the fault-injection DELAY VirtualService (labs/lab-10) — 'make clean-config' reverts
	@kubectl apply -f "$(MODULE_ROOT)/demo/resilience/virtualservice-fault-delay.yaml"

inject-errors: verify-cluster ## Apply the fault-injection ABORT VirtualService (labs/lab-10) — 'make clean-config' reverts
	@kubectl apply -f "$(MODULE_ROOT)/demo/resilience/virtualservice-fault-abort.yaml"

test: test-static ## Alias for 'make test-static' (the cluster-free default)
	@true

test-static: ## Offline validation via istioctl analyze/validate + shellcheck + YAML checks (no cluster required)
	@bash "$(MODULE_ROOT)/tests/static-validation.sh"

test-runtime: verify-cluster ## Full runtime test suite against a live cluster
	@bash "$(MODULE_ROOT)/tests/installation-test.sh"
	@for t in sidecar-injection-test ingress-test traffic-routing-test retry-timeout-test \
	          fault-injection-test circuit-breaking-test mtls-test authorization-test \
	          egress-test cilium-compatibility-test; do \
		echo "==> tests/$$t.sh"; \
		bash "$(MODULE_ROOT)/tests/$$t.sh" || exit 1; \
	done

status: ## Quick read-only status glance (control plane, gateway, demo app, proxy-status)
	@"$(MODULE_ROOT)/scripts/status.sh"

proxy-status: verify-cluster ## Run 'istioctl proxy-status'
	@istioctl proxy-status

proxy-config: verify-cluster ## Run 'istioctl proxy-config listeners <pod>' — pass POD=<name> NAMESPACE=<ns>
	@istioctl proxy-config listeners $${POD:?set POD=<pod-name>} -n $${NAMESPACE:-istio-demo}

analyze: verify-cluster ## Run 'istioctl analyze --all-namespaces'
	@istioctl analyze --all-namespaces

debug-bundle: verify-cluster ## Collect a sanitized troubleshooting bundle under .generated/debug-bundles/
	@"$(MODULE_ROOT)/scripts/collect-debug-bundle.sh"

clean-demo: verify-cluster ## Remove the demo/external namespaces and any temporary lab namespaces (Istio itself untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" demo

clean-config: verify-cluster ## Remove lab-applied Istio config objects (Istio itself untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" config

clean: verify-cluster ## Remove demo namespaces + lab-applied config (Istio itself untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" all

uninstall: verify-cluster ## DESTRUCTIVE: remove the Istio Helm releases and namespaces (CRDs kept unless REMOVE_CRDS=true)
	@echo "[WARN] DESTRUCTIVE: removing istio-ingress, istio-cni, istiod, istio-base Helm releases and their namespaces."
	@echo "[WARN] CRDs are kept by default — set REMOVE_CRDS=true to also delete them (deletes EVERY VirtualService/DestinationRule/etc. cluster-wide, not just this lab's own). Gateway API CRDs are only removed if this lab installed them."
	@REMOVE_CRDS="$(REMOVE_CRDS)" "$(MODULE_ROOT)/scripts/uninstall.sh"
