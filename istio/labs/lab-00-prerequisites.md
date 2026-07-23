# Lab 00: Prerequisites and Environment Verification

## Objective

Confirm your environment is ready before touching any Istio install step — this lab produces no cluster changes, only verification.

## Concepts exercised

Cluster-identity verification pattern (`../docs/04-istio-cni-and-cilium.md`'s prerequisite check), the Cilium CNI-chaining compatibility gap this repository has, and this module's overall safety model (never auto-modifying Cilium, never touching other modules).

## Prerequisites

- A running cluster matching `../config/endpoints.env`'s expected identity (API endpoint `192.168.56.10`, nodes `otel-control-plane`/`otel-worker-1`/`otel-worker-2`), provisioned by `../../auto-setup-default-kube-env/` (not by this module).
- `kubectl`, `helm` on your PATH.
- `istioctl` — see step 2 below if not yet installed.

## Steps

1. **Check prerequisite tooling**:
   ```bash
   cd istio
   make prerequisites
   ```
   This runs `scripts/check-prerequisites.sh` — verifies `kubectl`/`helm` presence and version, and that `istioctl` is installed (or tells you exactly how to install it, matching `scripts/install-istioctl.sh`'s checksum-verified, user-local pattern also used for Kyverno's CLI in `../../kyverno/`).

2. **Install istioctl if missing**:
   ```bash
   make install-istioctl
   ```
   Downloads the pinned version from `config/versions.env` (`ISTIOCTL_VERSION`), verifies its checksum against the published release checksum, and installs to `~/.local/bin` — no sudo required. Confirm with `istioctl version --remote=false`.

3. **Verify cluster identity**:
   ```bash
   make verify-cluster
   ```
   Runs `scripts/verify-cluster.sh` — hard-fails on API-endpoint/node-name/Cilium-health/CoreDNS-health mismatch (refusing to proceed against the wrong cluster), and **warns** (non-fatal at this stage) if Cilium isn't yet configured for CNI chaining.

4. **Read the Cilium CNI-chaining warning carefully if you see one.** This is expected on a cluster provisioned by `../../auto-setup-default-kube-env/` without the Phase 4 Cilium values applied yet — `../docs/04-istio-cni-and-cilium.md` explains exactly why, and gives the one manual `helm upgrade --reuse-values` command to run yourself before Lab 01. This module never runs that command for you.

## Validation

- `make prerequisites` and `make verify-cluster` both exit `0`, or print an actionable next step if not.
- `istioctl version --remote=false` prints the pinned version from `config/versions.env`.

## Cleanup

None — this lab makes no cluster changes.

## Reflection

Why does `verify-cluster.sh` treat a cluster-identity mismatch as a hard failure but treat the Cilium CNI-chaining gap as only a warning at this stage, while `scripts/install.sh` treats the same chaining check as a hard failure later? (See `../docs/04-istio-cni-and-cilium.md`.)
