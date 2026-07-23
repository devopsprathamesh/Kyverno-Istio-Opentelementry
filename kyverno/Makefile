# kyverno/ — Makefile
#
# Default target is `help`; it makes no changes. This module never
# invokes Vagrant and never creates/destroys the Kubernetes cluster —
# every install/runtime target requires `verify-cluster` to pass first,
# confirming this is the intended local learning cluster from
# ../auto-setup-default-kube-env, not just "a cluster exists".

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
MODULE_ROOT := $(shell cd "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))" && pwd)

LAB_PROFILE ?= recommended
VALID_PROFILES := minimum recommended

.PHONY: help prerequisites verify-cluster install install-minimum install-recommended \
        validate-installation deploy-demo apply-audit-policies apply-validate-policies \
        apply-mutate-policies apply-generate-policies apply-cleanup-policies \
        apply-exception-policies status reports test test-static test-runtime \
        clean-demo clean-policies clean uninstall _check-profile

help: ## Show this help (default target; makes no changes)
	@echo "kyverno — independent Kyverno hands-on lab"
	@echo
	@echo "Usage: make <target> [LAB_PROFILE=minimum|recommended]"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN{FS=":.*## "}{printf "  %-24s %s\n", $$1, $$2}'

_check-profile:
	@if ! echo " $(VALID_PROFILES) " | grep -q " $(LAB_PROFILE) "; then \
		echo "[FAIL] Invalid LAB_PROFILE='$(LAB_PROFILE)'. Valid values: $(VALID_PROFILES)"; \
		exit 1; \
	fi

prerequisites: ## Check required CLI tools (kubectl, helm, kyverno CLI) — read-only
	@"$(MODULE_ROOT)/scripts/check-prerequisites.sh"

verify-cluster: ## Confirm a reachable cluster exists AND is the intended local lab cluster
	@"$(MODULE_ROOT)/scripts/verify-cluster.sh"

install: _check-profile verify-cluster ## Install Kyverno via Helm (LAB_PROFILE=minimum|recommended)
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/install.sh"

install-minimum: ## Shortcut for 'make install LAB_PROFILE=minimum'
	@$(MAKE) --no-print-directory install LAB_PROFILE=minimum

install-recommended: ## Shortcut for 'make install LAB_PROFILE=recommended'
	@$(MAKE) --no-print-directory install LAB_PROFILE=recommended

validate-installation: verify-cluster ## Validate Kyverno controllers, CRDs, webhooks, and run functional probes
	@"$(MODULE_ROOT)/scripts/validate-installation.sh"

deploy-demo: verify-cluster ## Deploy demo workloads (applications/, insecure + compliant) to kyverno-demo
	@"$(MODULE_ROOT)/scripts/deploy-demo.sh"

apply-audit-policies: verify-cluster ## Apply policies/audit/
	@"$(MODULE_ROOT)/scripts/apply-policies.sh" audit

apply-validate-policies: verify-cluster ## Apply policies/validate/
	@"$(MODULE_ROOT)/scripts/apply-policies.sh" validate

apply-mutate-policies: verify-cluster ## Apply policies/mutate/
	@"$(MODULE_ROOT)/scripts/apply-policies.sh" mutate

apply-generate-policies: verify-cluster ## Apply policies/generate/
	@"$(MODULE_ROOT)/scripts/apply-policies.sh" generate

apply-cleanup-policies: verify-cluster ## Apply policies/cleanup/
	@"$(MODULE_ROOT)/scripts/apply-policies.sh" cleanup

apply-exception-policies: verify-cluster ## Apply policies/exceptions/
	@"$(MODULE_ROOT)/scripts/apply-policies.sh" exceptions

status: ## Quick read-only status glance (controllers, webhooks, policies, demo namespace)
	@"$(MODULE_ROOT)/scripts/status.sh"

reports: verify-cluster ## Summarize PolicyReport/ClusterPolicyReport violations
	@"$(MODULE_ROOT)/scripts/collect-policy-reports.sh"

test: test-static ## Alias for 'make test-static' (the cluster-free default)
	@true

test-static: ## Offline policy validation via the Kyverno CLI (no cluster required)
	@bash "$(MODULE_ROOT)/tests/static-validation.sh"

test-runtime: verify-cluster ## Full runtime test suite against a live cluster
	@"$(MODULE_ROOT)/scripts/run-tests.sh"

clean-demo: verify-cluster ## Remove the demo namespace and any temporary lab namespaces (Kyverno itself untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" demo

clean-policies: verify-cluster ## Remove applied lab policies (Kyverno itself untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" policies

clean: verify-cluster ## Remove demo namespace + applied policies (Kyverno itself untouched)
	@"$(MODULE_ROOT)/scripts/clean.sh" all

uninstall: verify-cluster ## DESTRUCTIVE: remove the Kyverno Helm release and namespace (CRDs kept unless REMOVE_CRDS=true)
	@echo "[WARN] DESTRUCTIVE: removing the Kyverno Helm release and namespace '$(shell grep KYVERNO_NAMESPACE config/namespaces.env | cut -d= -f2)'."
	@echo "[WARN] CRDs are kept by default — set REMOVE_CRDS=true to also delete them (this deletes EVERY ClusterPolicy/Policy/PolicyException/PolicyReport cluster-wide, not just this lab's own)."
	@REMOVE_CRDS="$(REMOVE_CRDS)" "$(MODULE_ROOT)/scripts/uninstall.sh"
