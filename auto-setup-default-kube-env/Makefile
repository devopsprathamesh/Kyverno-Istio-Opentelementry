# auto-setup-default-kube-env — Makefile
#
# Default target is `help`; it makes no changes to the system. Every
# target below is self-documented with a trailing "## description"
# comment, parsed by `make help`.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
MODULE_ROOT := $(shell cd "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))" && pwd)

LAB_PROFILE ?= recommended
VALID_PROFILES := minimum recommended

.PHONY: help prerequisites setup vm-up vm-status validate status kubeconfig \
        cilium-status hubble-status storage-test network-test \
        ssh-control-plane ssh-worker-1 ssh-worker-2 \
        provision reload halt destroy rebuild reset-cluster clean-generated \
        _check-profile

help: ## Show this help (default target; makes no changes)
	@echo "auto-setup-default-kube-env — reusable Kubernetes lab platform"
	@echo
	@echo "Usage: make <target> [LAB_PROFILE=minimum|recommended]"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN{FS=":.*## "}{printf "  %-20s %s\n", $$1, $$2}'

_check-profile:
	@if ! echo " $(VALID_PROFILES) " | grep -q " $(LAB_PROFILE) "; then \
		echo "[FAIL] Invalid LAB_PROFILE='$(LAB_PROFILE)'. Valid values: $(VALID_PROFILES)"; \
		exit 1; \
	fi

prerequisites: _check-profile ## Run host prerequisite checks (read-only, no side effects)
	@"$(MODULE_ROOT)/scripts/host/check-prerequisites.sh" "$(LAB_PROFILE)"

setup: _check-profile ## Full ordered setup: prerequisites -> control plane -> workers -> storage -> validate
	@LAB_PROFILE="$(LAB_PROFILE)" "$(MODULE_ROOT)/scripts/host/setup-cluster.sh" "$(LAB_PROFILE)"

vm-up: _check-profile ## Bring up all 3 VMs via a single 'vagrant up' (no explicit ordering guarantee — prefer 'make setup')
	@cd "$(MODULE_ROOT)" && LAB_PROFILE="$(LAB_PROFILE)" vagrant up

vm-status: ## Show VirtualBox/Vagrant VM state only
	@cd "$(MODULE_ROOT)" && vagrant status

validate: ## Run the full validation suite (VM/OS/Kubernetes/Cilium/storage/host-access layers)
	@"$(MODULE_ROOT)/scripts/host/validate-cluster.sh"

status: ## Quick read-only status glance (VM state, nodes, Cilium, storage)
	@"$(MODULE_ROOT)/scripts/host/status.sh"

kubeconfig: ## Confirm/normalize the exported kubeconfig and print usage instructions
	@"$(MODULE_ROOT)/scripts/host/export-kubeconfig.sh"

cilium-status: ## Run 'cilium status --wait' on the control plane
	@cd "$(MODULE_ROOT)" && vagrant ssh $$(grep CONTROL_PLANE_NAME config/cluster.env | cut -d= -f2) \
		-c "sudo KUBECONFIG=/etc/kubernetes/admin.conf cilium status --wait"

hubble-status: ## Run 'hubble status' against Hubble Relay on the control plane
	@cd "$(MODULE_ROOT)" && CP=$$(grep CONTROL_PLANE_NAME config/cluster.env | cut -d= -f2); \
		vagrant ssh $$CP -c "sudo kubectl -n kube-system port-forward deployment/hubble-relay 4245:4245 >/tmp/hubble-pf.log 2>&1 & sleep 3; HUBBLE_ADDRESS=localhost:4245 hubble status; kill %1"

storage-test: ## Run the storage dynamic-PVC test suite
	@bash "$(MODULE_ROOT)/tests/storage-test.sh"

network-test: ## Run the pod/service/DNS/NetworkPolicy network test suite
	@bash "$(MODULE_ROOT)/tests/network-test.sh"

ssh-control-plane: ## SSH into otel-control-plane
	@cd "$(MODULE_ROOT)" && vagrant ssh $$(grep CONTROL_PLANE_NAME config/cluster.env | cut -d= -f2)

ssh-worker-1: ## SSH into otel-worker-1
	@cd "$(MODULE_ROOT)" && vagrant ssh $$(grep WORKER1_NAME config/cluster.env | cut -d= -f2)

ssh-worker-2: ## SSH into otel-worker-2
	@cd "$(MODULE_ROOT)" && vagrant ssh $$(grep WORKER2_NAME config/cluster.env | cut -d= -f2)

provision: ## Re-run provisioning scripts on all VMs (idempotent; does not re-init/re-join if already done)
	@cd "$(MODULE_ROOT)" && vagrant provision

reload: ## Restart all VMs and re-run provisioning (vagrant reload --provision)
	@cd "$(MODULE_ROOT)" && vagrant reload --provision

halt: ## Power off all VMs without destroying them (state is preserved; see 'make destroy')
	@echo "[INFO] Halting VMs — disk state preserved, no data is destroyed. Resume with 'make vm-up'."
	@cd "$(MODULE_ROOT)" && vagrant halt

destroy: ## DESTRUCTIVE: delete all 3 VMs and their disks permanently (cluster state is lost)
	@echo "[WARN] DESTRUCTIVE: this deletes otel-control-plane, otel-worker-1, otel-worker-2 and all their disk state permanently."
	@cd "$(MODULE_ROOT)" && vagrant destroy -f
	@echo "[INFO] VMs destroyed. .generated/ was NOT cleaned — run 'make clean-generated' if you also want that removed."

rebuild: _check-profile ## DESTRUCTIVE: destroy then fully re-run 'make setup' from scratch
	@echo "[WARN] DESTRUCTIVE: destroying existing VMs before rebuilding."
	@$(MAKE) --no-print-directory destroy
	@$(MAKE) --no-print-directory setup LAB_PROFILE="$(LAB_PROFILE)"

reset-cluster: ## DESTRUCTIVE: kubeadm reset on every node without recreating VMs (see docs/REBUILD-AND-RECOVERY.md)
	@echo "[WARN] DESTRUCTIVE: this runs 'kubeadm reset' on all 3 nodes, wiping cluster state while keeping the VMs. See docs/REBUILD-AND-RECOVERY.md before using this."
	@cd "$(MODULE_ROOT)" && \
		for n in $$(grep -E '^(CONTROL_PLANE|WORKER1|WORKER2)_NAME' config/cluster.env | cut -d= -f2); do \
			echo "[INFO] kubeadm reset on $$n"; \
			vagrant ssh $$n -c "sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d /var/lib/cni /etc/kubernetes /var/lib/kubelet/*" || true; \
		done
	@echo "[INFO] Reset complete. Re-run 'make setup' to reinitialize the cluster on the existing VMs."

clean-generated: ## Remove .generated/ contents only (kubeconfig, join command, reports) — never touches tracked files or VMs
	@"$(MODULE_ROOT)/scripts/host/cleanup-generated-files.sh"
