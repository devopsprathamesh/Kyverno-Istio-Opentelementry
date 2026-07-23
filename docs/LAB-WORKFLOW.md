# Planned Lab Workflow

This document defines the intended end-to-end learning sequence across all modules, and the rules for when to reuse the existing cluster versus reset or rebuild it. It describes **planned** workflow — the Makefile targets referenced below are conventions defined in [`REPOSITORY-GOVERNANCE.md`](REPOSITORY-GOVERNANCE.md) and are not yet implemented (see [`PROJECT-IMPLEMENTATION-PLAN.md`](../PROJECT-IMPLEMENTATION-PLAN.md)).

## Sequence

1. **Provision the Kubernetes base environment** — `auto-setup-default-kube-env/`: bring up the three VMs, bootstrap Kubernetes with kubeadm, install Cilium/Hubble, export kubeconfig. This is the one long-lived step; everything after it targets the same cluster until an explicit reset/rebuild is called for.
2. **Validate Cilium and Hubble** — confirm all nodes `Ready`, Cilium agent/operator healthy, Hubble flow visibility working (`cilium status`, `hubble observe`) before installing anything else. This is the known-clean baseline every later phase is measured against.
3. **Run the Kyverno lab independently** — install Kyverno into its own namespace, work through validate/mutate/generate/verifyImages policies and policy exceptions, observe policy reports.
4. **Clean Kyverno resources** — `make uninstall`/`clean` in `kyverno/`; confirm no residual CRDs, webhook configurations, or namespace remain before moving on, so the Istio lab starts from the same known-clean baseline.
5. **Run the Istio lab independently** — install Istio (sidecar mode), enable injection on the demo namespace, work through traffic management, mTLS, and authorization policy.
6. **Clean Istio resources** — `make uninstall`/`clean` in `istio/`; confirm sidecar injection is disabled and no residual Istio CRDs/webhooks remain.
7. **Run the observability lab independently** — install the OpenTelemetry Operator/Collector, Prometheus, Grafana, Jaeger, Loki; instrument a demo workload; validate all three signals end to end, including the `filelog` log path.
8. **Clean the observability stack** — `make uninstall`/`clean` in `opentelemetry-prometheus-grafana-jaeger-loki/`; confirm no residual Collector DaemonSets, CRDs, or PVCs remain (PVCs in particular are easy to leave behind and silently consume disk).
9. **Rebuild or reset the base cluster** — before starting the integrated lab, reset the cluster to the known-clean baseline validated in step 2 (see "When to reset vs. rebuild" below), so the integrated lab's results are attributable to the integrated configuration, not leftover state from the independent labs.
10. **Run the all-tools integrated lab** — install Cilium-level policy, Kyverno, Istio, and the observability stack together against shared demo services; exercise production-style failure scenarios.
11. **Run repository-wide validation** — confirm every module's validation passes together, documentation links resolve, and [`VALIDATION-STATUS.md`](VALIDATION-STATUS.md) reflects the final state of the repository for this pass.

## When to reuse the same cluster

Reuse the existing cluster (no reset) when moving between steps that only add/remove one tool at a time and that tool's `clean`/`uninstall` target has been run and validated as complete — e.g., after step 4 (Kyverno cleaned) before starting step 5 (Istio). The base platform (Cilium/Hubble, kubeadm, node OS) is expensive to rebuild and is not implicated by a single tool's install/uninstall cycle.

## When to uninstall a tool

Uninstall a tool (rather than resetting the whole cluster) whenever you are done with that tool's independent lab and are not yet ready to combine it with others — this is the normal step 4/6/8 pattern above. Also uninstall (and reinstall) a tool whenever its lab left the cluster in a state you cannot otherwise explain, before assuming the cluster itself is broken.

## When to reset Kubernetes

Reset Kubernetes (`kubeadm reset` and re-`init`/`join`, without recreating the VMs) when:
- Multiple tools' cleanup left ambiguous residual state (e.g., stuck `Terminating` namespaces, orphaned webhook configurations) that individual `uninstall` targets could not resolve.
- You are about to start the integrated lab (step 9) and want a cluster-level guarantee of a clean baseline rather than trusting every prior `clean` target ran correctly.

## When to recreate VMs

Recreate the VMs (`vagrant destroy && vagrant up`, full re-provisioning) when:
- A `kubeadm reset` does not resolve cluster health (e.g., corrupted containerd state, disk pressure from accumulated image layers).
- You are changing base-layer configuration itself (Ubuntu version, Kubernetes minor version, Cilium version) rather than what's installed on top of it — this is a deliberate re-validation of the base platform, not a cleanup step.
- You want to reclaim disk space consumed by image layers and volumes across many lab iterations.

## When to use a clean cluster

Use a genuinely clean cluster (fresh reset or rebuild, not just tool-level uninstall) for:
- The integrated lab (step 10), so its results are attributable to the integrated configuration.
- Any time you are specifically trying to reproduce or debug an installation-order-dependent issue — reusing a cluster that has had things installed and removed multiple times can mask ordering bugs that a clean install would surface.

## Avoid VM snapshots

Do not rely on VirtualBox VM-level snapshots as a substitute for the automation's own provisioning/reset/rebuild scripts. Snapshots capture disk and memory state opaquely and make it easy to silently drift from what the actual provisioning automation produces — defeating the reproducibility goal behind [ADR-010](DECISIONS.md#adr-010-version-pinning) and this repository's emphasis on scripted, re-runnable setup. If a snapshot is used for a quick throwaway experiment, treat the result as disposable and re-provision from scratch before trusting or documenting any outcome from it.

## Use Vagrant snapshots only with caution

`vagrant snapshot save`/`restore` is less opaque than a raw VirtualBox snapshot (it's still scoped to the Vagrant-managed VM lifecycle) and can be useful to quickly bookmark "cluster just after Cilium validated" during active development of the base environment automation itself. However:
- Never treat a restored snapshot as equivalent to a freshly provisioned cluster for validation purposes recorded in [`VALIDATION-STATUS.md`](VALIDATION-STATUS.md) — only a real `vagrant up` from scratch (or documented reset) counts as a validated provisioning run.
- Snapshots taken mid-lab (e.g., with Kyverno half-installed) are especially risky to restore from later, since they can reintroduce exactly the residual-state problems the reset/rebuild guidance above is meant to avoid.
- Prefer the automation's own idempotent `setup`/`validate` targets over snapshot restore for anything that will be documented or shared.
