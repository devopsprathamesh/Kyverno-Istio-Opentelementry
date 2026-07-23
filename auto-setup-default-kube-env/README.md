# auto-setup-default-kube-env

Reusable, tool-neutral Kubernetes lab platform: VirtualBox + Vagrant + Ubuntu Server LTS + containerd + kubeadm + Cilium/Hubble. Every other module in this repository ([`../kyverno/`](../kyverno/), [`../istio/`](../istio/), [`../opentelemetry-prometheus-grafana-jaeger-loki/`](../opentelemetry-prometheus-grafana-jaeger-loki/), [`../all-tools-integrated-lab/`](../all-tools-integrated-lab/)) installs against the cluster this module produces — it never installs Kyverno, Istio, or any observability component itself.

## Purpose

Give every downstream lab in this repository a single, reproducible, disposable Kubernetes cluster to build on, so each of them can focus on its own tool without also having to re-solve "how do I get a Kubernetes cluster" — and so that cluster can be reset to a known-clean baseline between labs. See root [`../docs/DECISIONS.md` ADR-001](../docs/DECISIONS.md#adr-001-one-reusable-kubernetes-foundation).

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for this module's internal script/config architecture, and root [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §3–4 for the repository-wide view (topology, Cilium/Hubble networking, how this module fits into the overall dependency graph).

## VM topology

| VM name | Hostname | Kubernetes role | Private IP |
| --- | --- | --- | --- |
| `otel-control-plane` | `otel-control-plane` | Control plane | `192.168.56.10` |
| `otel-worker-1` | `otel-worker-1` | Worker | `192.168.56.11` |
| `otel-worker-2` | `otel-worker-2` | Worker | `192.168.56.12` |

Each VM has a NAT adapter (internet egress) and a host-only adapter (`192.168.56.0/24`, stable static IP, cluster communication) — see [`docs/NETWORKING.md`](docs/NETWORKING.md).

## Resource profiles

| Profile | Control plane | Worker 1 | Worker 2 | Target host RAM |
| --- | --- | --- | --- | --- |
| `minimum` | 2 vCPU / 3072MB | 2 vCPU / 3072MB | 2 vCPU / 3072MB | ~16GB |
| `recommended` (default) | 2 vCPU / 4096MB | 4 vCPU / 7168MB | 4 vCPU / 7168MB | ~32GB |

Select with `LAB_PROFILE=minimum|recommended`; override individual node CPU/RAM via env vars without editing tracked files — see [`.env.example`](.env.example) and [`examples/profile-overrides.env.example`](examples/profile-overrides.env.example).

## Host prerequisites

VirtualBox, Vagrant, `git`, `make`, `curl`, `ssh` on a host with hardware virtualization support. Run `make prerequisites` for a full, read-only check (RAM, disk, existing VirtualBox/Vagrant state, host-only network conflicts) before doing anything else — see [`docs/INSTALLATION.md`](docs/INSTALLATION.md).

## Version matrix

Pinned in [`config/versions.env`](config/versions.env) (the single source every script loads from); full sourcing/compatibility detail in root [`../docs/VERSIONS.md`](../docs/VERSIONS.md). Summary: Ubuntu 24.04 (`bento/ubuntu-24.04`), Kubernetes 1.35.6, containerd 2.3.3, Cilium 1.19.3 (+ Cilium CLI 0.19.5), Helm 4.2.3, Rancher local-path-provisioner 0.0.26.

## Quick start

```bash
cd ~/github/Kyverno-Istio-Opentelementry/auto-setup-default-kube-env
make prerequisites
make setup LAB_PROFILE=recommended
make validate
export KUBECONFIG="$(pwd)/.generated/kubeconfig"
kubectl get nodes -o wide
```

## Detailed setup

See [`docs/INSTALLATION.md`](docs/INSTALLATION.md) for the full setup orchestration diagram, direct Vagrant commands, the complete Makefile reference, kubeconfig usage, and Cilium/Hubble/network/storage validation commands.

## Direct Vagrant commands

```bash
LAB_PROFILE=minimum vagrant up otel-control-plane
vagrant status
vagrant ssh otel-worker-1
VAGRANT_GUI=true vagrant up otel-control-plane   # show the VirtualBox console instead of headless
```

## Makefile commands

Run `make help` for the authoritative, current list. See [`docs/INSTALLATION.md`](docs/INSTALLATION.md) for a description of each.

## kubeconfig usage

```bash
export KUBECONFIG="$(pwd)/.generated/kubeconfig"
kubectl get nodes -o wide
```

The exported kubeconfig grants cluster-admin access — treat it as a credential (git-ignored, mode 600, never printed by any script). See [`docs/INSTALLATION.md`](docs/INSTALLATION.md) "kubeconfig usage".

## Cilium validation

```bash
make cilium-status
```

See [`docs/CILIUM-HUBBLE.md`](docs/CILIUM-HUBBLE.md) for the full architecture (agent/operator/identity model, kube-proxy coexistence) and CLI/UI access.

## Hubble usage

```bash
make hubble-status
```

## Network validation

```bash
make network-test
```

## Storage validation

```bash
make storage-test
```

See [`docs/STORAGE.md`](docs/STORAGE.md) for what's actually exercised and this module's storage limitations (no HA, node-pinned data, full loss on VM destroy).

## VM access

```bash
make ssh-control-plane
make ssh-worker-1
make ssh-worker-2
```

## Halt and resume

```bash
make halt    # power off, disk state preserved
make vm-up   # power back on
```

## Rebuild and recovery

```bash
make destroy && make setup LAB_PROFILE=recommended   # full rebuild
make reset-cluster                                     # kubeadm reset only, VMs kept
```

Full decision tree (when to halt/resume vs. reprovision vs. full rebuild vs. rebuild one worker vs. `kubeadm reset`) in [`docs/REBUILD-AND-RECOVERY.md`](docs/REBUILD-AND-RECOVERY.md).

## Cleanup

```bash
make clean-generated   # removes .generated/ contents only — VMs untouched
make destroy             # DESTRUCTIVE — deletes all 3 VMs and disks
```

## Troubleshooting

[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — symptom/diagnostic/cause/resolution/validation table covering VM, OS, containerd, Kubernetes, Cilium/Hubble, storage, and host-access failure modes.

## Security limitations

Cluster-admin kubeconfig, no in-cluster RBAC restriction (left to downstream tool modules), unencrypted host-only network appropriate only for a single-host local lab. Full list in [`docs/INSTALLATION.md`](docs/INSTALLATION.md) "Security limitations".

## Local-lab limitations

Single control-plane node (no HA), local-path storage with no redundancy, static IPs assuming sole use of `192.168.56.0/24` on your machine. Full list in [`docs/INSTALLATION.md`](docs/INSTALLATION.md) "Local-lab limitations".

## Definition of done

See [`../PROJECT-IMPLEMENTATION-PLAN.md`](../PROJECT-IMPLEMENTATION-PLAN.md) Phase 2 and [`../docs/VALIDATION-STATUS.md`](../docs/VALIDATION-STATUS.md) for the authoritative, current status of this module — including exactly what has and hasn't been validated against a live cluster yet.

## Next learning modules

1. [`../kyverno/`](../kyverno/)
2. [`../istio/`](../istio/)
3. [`../opentelemetry-prometheus-grafana-jaeger-loki/`](../opentelemetry-prometheus-grafana-jaeger-loki/)
4. [`../all-tools-integrated-lab/`](../all-tools-integrated-lab/)

See root [`../docs/LAB-WORKFLOW.md`](../docs/LAB-WORKFLOW.md) for the full recommended sequence.
