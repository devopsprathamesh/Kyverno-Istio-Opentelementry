# Architecture Decision Records

Each ADR follows: Status, Context, Decision, Alternatives considered, Consequences, Risks, Validation requirements.

## ADR-001: One reusable Kubernetes foundation

**Status:** Accepted

**Context:** This repository teaches four distinct tool domains (policy, service mesh, observability, and their integration) on top of Kubernetes. Each domain has its own install/validate/cleanup lifecycle, and learners will repeat that lifecycle many times while learning.

**Decision:** Provision exactly one reusable Kubernetes platform in `auto-setup-default-kube-env/`, kept strictly tool-neutral (no Kyverno/Istio/observability), and have every other module install against it rather than provisioning its own cluster.

**Alternatives considered:**
- A separate cluster per module — rejected: multiplies VM/resource cost, and cross-module comparisons (e.g., "how much overhead does Istio add on top of a known-clean baseline") become impossible.
- Bundling tool installation into the base provisioning automation — rejected: makes it impossible to learn or validate any single tool's install/cleanup lifecycle in isolation.

**Consequences:** Every tool module's automation must be idempotent and safely re-runnable against the same long-lived cluster; base provisioning automation must be robust enough to reset/rebuild cleanly when a lab leaves the cluster in a bad state.

**Risks:** A base-cluster bug affects every downstream module simultaneously. State accumulated by one lab (leftover CRDs, namespaces) could leak into another if cleanup automation is incomplete.

**Validation requirements:** Base cluster must pass its own validation (node readiness, CNI health) before any tool module install begins; each tool module's `make uninstall`/`clean` must be verified to leave no residual CRDs, namespaces, or webhook configurations.

## ADR-002: Cilium as the primary CNI

**Status:** Accepted

**Context:** The base platform needs a CNI. The target learner already understands traditional iptables-based networking from production experience but is not assumed to know eBPF-based networking or Cilium/Hubble specifically.

**Decision:** Use Cilium as the primary CNI, with Hubble enabled for flow visibility, per the version and compatibility detail in [`VERSIONS.md`](VERSIONS.md) and [`DEPENDENCIES.md`](DEPENDENCIES.md).

**Alternatives considered:**
- Calico — rejected as the primary choice: strong NetworkPolicy support but without Cilium's eBPF-native L7 visibility and Hubble tooling, which is directly pedagogically relevant to later Istio/Kyverno network troubleshooting.
- Flannel — rejected: no NetworkPolicy enforcement of its own, which is a hard requirement for the security-relevant portions of this curriculum (Istio AuthorizationPolicy interplay, Kyverno-governed NetworkPolicy).

**Consequences:** Learners get first-class flow visibility (Hubble) as a troubleshooting tool for every later phase, including diagnosing Istio and Kyverno interactions at the network layer. The curriculum takes on eBPF/Cilium as an explicit teaching surface rather than treating the CNI as a black box.

**Risks:** eBPF features have kernel version dependencies that must be validated against the chosen Ubuntu Server LTS kernel; not every advanced Cilium feature (e.g., WireGuard encryption) is guaranteed to work out of the box on the base VM image.

**Validation requirements:** Cilium and Hubble health checks (`cilium status`, `hubble observe`) must pass on all three nodes before any tool module is installed.

## ADR-003: Retain kube-proxy initially

**Status:** Accepted

**Context:** Cilium supports full kube-proxy replacement, which is a well-regarded production pattern but changes how service routing and API-server reachability work at a level that is easy to misconfigure while still learning the basics of Cilium.

**Decision:** Retain kube-proxy for the initial default profile. Document a kube-proxy-replacement profile as an explicit, advanced, opt-in configuration for later exploration — never the default.

**Alternatives considered:** Default to full kube-proxy replacement from the start — rejected: couples two learning curves (Cilium fundamentals and kube-proxy replacement's stricter bootstrap requirements) in the default path, increasing the chance of an unrecoverable early failure for a learner still building Cilium fundamentals.

**Consequences:** The default cluster looks more like a typical production cluster most learners have already operated (kube-proxy present), lowering the number of simultaneously new concepts.

**Risks:** Learners who only ever use the default profile will not get hands-on kube-proxy-replacement experience unless they deliberately opt into the advanced profile.

**Validation requirements:** Default profile validation must confirm kube-proxy and Cilium coexist correctly (Service ClusterIPs resolve and load-balance as expected); the advanced profile, when documented, must include its own separate validation steps.

## ADR-004: Independent labs plus one integrated lab

**Status:** Accepted

**Context:** Kyverno, Istio, and the observability stack are each substantial enough to teach on their own, but a senior engineer also needs to see how they interact and potentially conflict when combined — which is what production environments actually look like.

**Decision:** Build each tool as a fully independent, installable/removable lab first, and build one final integrated lab that combines all of them, reusing configuration already validated independently rather than re-deriving it.

**Alternatives considered:**
- Combine everything into a single lab from the start — rejected: makes it impossible to isolate which tool caused a given failure while learning, and front-loads integration complexity before the fundamentals of any one tool are solid.
- Skip the integrated lab entirely — rejected: leaves out the most production-relevant scenario (multiple admission/policy/proxy layers interacting on the same traffic), which is explicitly requested as part of this curriculum's value.

**Consequences:** Total build effort is higher (five modules instead of one), but each module is independently debuggable and the integrated lab's failure modes are more clearly attributable, since the individual pieces are already known-good.

**Risks:** Configuration drift between what was validated independently and what is reused in the integrated lab, if the integrated lab's reuse mechanism (copy vs. reference) is not disciplined.

**Validation requirements:** The integrated lab's definition of done explicitly requires citing which independent-lab artifacts were reused, not regenerated.

## ADR-005: Istio sidecar mode first

**Status:** Accepted

**Context:** Istio now offers both sidecar mode (per-pod Envoy proxy) and ambient mode (proxy-less data plane using shared node-level and per-namespace waypoint proxies), and upstream currently presents both as production-viable.

**Decision:** Implement the Istio lab in sidecar mode first. Document ambient mode as a later, advanced lab addition rather than the initial implementation.

**Alternatives considered:** Start with ambient mode — rejected for this curriculum specifically because sidecar mode's per-pod proxy model maps more directly onto concepts the target learner already has (a sidecar container is a familiar Kubernetes pattern), while ambient's shared-proxy architecture is a bigger conceptual jump best taken after sidecar fundamentals (mTLS, traffic policy, AuthorizationPolicy) are solid. This is a pedagogical sequencing choice, not a statement that ambient is less mature — see the explicit note in [`VERSIONS.md`](VERSIONS.md#items-flagged-as-uncertain-compatibility-do-not-treat-as-resolved).

**Consequences:** The first Istio lab's traffic-interception model (iptables or CNI-plugin redirection into per-pod Envoy) is what later gets validated against Cilium in the integrated lab (see [`DEPENDENCIES.md`](DEPENDENCIES.md) §8); an ambient-mode lab would face a different, not-yet-documented set of Cilium-interaction questions.

**Risks:** None specific to sidecar mode's maturity; the risk is scope, not stability — an ambient-mode addition is explicitly out of scope until the sidecar lab and its integrated-lab interactions are fully validated.

**Validation requirements:** Sidecar injection, mTLS, and AuthorizationPolicy enforcement must all be validated in the independent Istio lab before the integrated lab attempts to layer Kyverno and Cilium NetworkPolicy on top.

## ADR-006: OpenTelemetry Collector agent-and-gateway architecture

**Status:** Accepted

**Context:** Telemetry (traces, metrics, logs, and node log files) needs to be collected from every node and pod, enriched with Kubernetes metadata, and routed to three different backends (Prometheus, Jaeger, Loki).

**Decision:** Deploy the OpenTelemetry Collector twice, in two roles: a **Collector Agent** as a per-node DaemonSet (local OTLP receiver and `filelog` tailer), and a **Collector Gateway** as a central Deployment (Kubernetes metadata enrichment, backend-specific export, buffering/retry).

**Alternatives considered:**
- A single Collector Deployment with no per-node agent — rejected: forces every application pod to reach a small number of central Collector pods directly over the network for every span/metric/log, and cannot tail node-local `/var/log/pods` files at all (log files are node-local, so a `filelog` receiver *must* run per node).
- Per-node agents only, no central gateway — rejected: pushes backend-specific export configuration (Prometheus remote-write, Jaeger OTLP, Loki OTLP) and its credentials/retry logic onto every node instead of one central, more easily managed location; complicates backend migrations later.

**Consequences:** Two Collector configurations to maintain instead of one, but each has a narrow, well-defined job (agent: local collection; gateway: enrichment + fan-out), which is easier to reason about and scale independently.

**Risks:** The agent-to-gateway hop is an additional network path that can itself drop or delay telemetry if under-provisioned; gateway must be scaled/monitored like any other critical data-plane service.

**Validation requirements:** End-to-end delivery for all three signals must be validated from application through agent through gateway to each backend, not just agent-to-backend or gateway health in isolation.

## ADR-007: Filelog receiver for Kubernetes log collection

**Status:** Accepted

**Decision:** Use the OpenTelemetry Collector `filelog` receiver, tailing `/var/log/pods/**` on each node, as the sole log-collection mechanism — no sidecar log-shipping containers, no `kubectl logs`-based collection, no separate log agent (e.g., Fluent Bit) running alongside the Collector.

**Context:** Kubernetes writes every container's stdout/stderr to node-local files in a well-defined location and format (CRI log format); this is the same underlying source `kubectl logs` and every other Kubernetes log-shipping tool reads from.

**Alternatives considered:**
- A sidecar log-shipping container per application pod — rejected: multiplies the number of running containers per pod, duplicates configuration across every workload, and is redundant with data the node already writes to disk.
- A dedicated third-party log agent (e.g., Fluent Bit, Vector) instead of the Collector's own `filelog` receiver — rejected for this repository specifically: it would mean two entirely different agent technologies for logs versus traces/metrics, doubling the operational surface area this curriculum has to teach, when the Collector's own `filelog` receiver is capable of the same job and keeps one unified collection technology across all three signals.

**Consequences:** All three signals (traces, metrics, logs) share one collection technology (the OpenTelemetry Collector) end to end, which is a deliberate simplification for teaching purposes and matches the architecture in [`ARCHITECTURE.md`](ARCHITECTURE.md#7-filelog-receiver-flow-kubernetes-log-ingestion).

**Risks:** The `filelog` receiver's CRI/container parsing and file-rotation handling are contrib-component features that change between Collector `v0.x` releases (see [`VERSIONS.md`](VERSIONS.md)) and must be re-tested on every Collector version bump.

**Validation requirements:** Verify that pod restarts, log rotation, and high-throughput logging pods do not cause log loss or duplication under the pinned `filelog` configuration.

## ADR-008: Loki as the log backend

**Status:** Accepted

**Context:** Grafana can visualize logs but does not itself store or index them; a dedicated log storage/query backend is required, and it needs to accept the OTLP-formatted, Kubernetes-enriched records produced by the `filelog` pipeline (ADR-007).

**Decision:** Use Loki as the log storage and query backend, ingesting via its native OTLP endpoint (`/otlp`).

**Alternatives considered:**
- Elasticsearch/OpenSearch — rejected as the default: heavier operational footprint (dedicated indexing cluster) than this lab's scope justifies, and full-text indexing is not needed when Loki's label-based, log-stream indexing model is sufficient for this curriculum's query patterns (LogQL alongside PromQL-like label selection).
- Storing logs in Prometheus/a metrics backend — not a real alternative: Prometheus is not a log store; mentioned here only to make explicit why a separate backend is required at all.

**Consequences:** LogQL becomes a second query language learners need alongside PromQL; in exchange, Loki's label-indexing model directly parallels Prometheus's, which is a deliberate teaching parallel (see [`LAB-WORKFLOW.md`](LAB-WORKFLOW.md)).

**Risks:** Loki's storage-schema configuration must be planned explicitly per [`DEPENDENCIES.md`](DEPENDENCIES.md) §11; a wrong schema choice for the lab's storage backend can require a full re-ingestion to fix.

**Validation requirements:** Confirm OTLP ingestion at `/otlp` succeeds with Kubernetes-enriched structured metadata intact, and that Grafana can query the result via LogQL.

## ADR-009: Prometheus, Jaeger, Loki, and Grafana responsibilities

**Status:** Accepted

**Context:** With four observability tools in play, it must be unambiguous which one is responsible for storage, querying, collection, and visualization of each signal, to avoid learners (or later contributors) building redundant paths.

**Decision:**
- **Collection** (all three signals): OpenTelemetry Collector (agent + gateway), per ADR-006.
- **Storage + query — metrics:** Prometheus (PromQL).
- **Storage + query — traces:** Jaeger (its own trace storage/query API, fed via OTLP).
- **Storage + query — logs:** Loki (LogQL), per ADR-008.
- **Visualization only, all three signals:** Grafana. Grafana holds no signal data of its own beyond its own dashboard/provisioning state.

**Alternatives considered:** Using Grafana's own backends (Mimir/Tempo) instead of Prometheus/Jaeger — rejected as out of scope: this curriculum is explicitly scoped to Prometheus, Grafana, Jaeger, and Loki by name, and Mimir/Tempo are different products with their own separate learning curve.

**Consequences:** Clean separation of concerns makes it straightforward to reason about and troubleshoot each signal's path independently, and matches the flows diagrammed in [`ARCHITECTURE.md`](ARCHITECTURE.md).

**Risks:** None specific beyond the individual component risks already listed in [`VERSIONS.md`](VERSIONS.md) and [`DEPENDENCIES.md`](DEPENDENCIES.md).

**Validation requirements:** For each signal, confirm the backend listed above is the only place that signal is durably stored, and that Grafana's data-source config points at exactly that backend.

## ADR-010: Version pinning

**Status:** Accepted

**Context:** This repository is a teaching artifact meant to produce reproducible, explainable results; floating `latest` tags silently change behavior between runs and make failures impossible to reliably reproduce or roll back.

**Decision:** Pin every component to an exact release version everywhere a version can be specified (VM base image, Helm chart `--version`, container image tags). Never use `latest` or an unpinned floating tag. Record the pinned version, its source, and its compatibility notes in [`VERSIONS.md`](VERSIONS.md).

**Alternatives considered:** Track upstream `latest`/rolling channels to always demonstrate the newest features — rejected: directly conflicts with reproducibility, and would make this document's compatibility research stale by construction rather than by omission.

**Consequences:** Every version bump becomes a deliberate, documented action (updating `VERSIONS.md` and re-validating), rather than an implicit side effect of re-running automation on a different day.

**Risks:** Pinned versions will fall behind upstream security patches over time; the repository must periodically revisit `VERSIONS.md` rather than treating it as a one-time artifact.

**Validation requirements:** Any install script or Helm command that does not pass an explicit version is a governance violation (see [`REPOSITORY-GOVERNANCE.md`](REPOSITORY-GOVERNANCE.md)) and must be corrected before merge.

## ADR-011: Cilium cluster-pool IPAM without a kubeadm `podSubnet`

**Status:** Accepted

**Context:** `kubeadm init` supports a `--pod-network-cidr`/`ClusterConfiguration.networking.podSubnet` flag that some CNIs (Flannel, Calico in certain modes) consume to have kube-controller-manager allocate per-node CIDRs (`--allocate-node-cidrs`). Cilium does not need this: its default `cluster-pool` IPAM mode has its own operator-driven allocator that assigns per-node pod CIDRs directly, independent of kube-controller-manager.

**Decision:** Do not set `podSubnet` in `auto-setup-default-kube-env/config/kubeadm-config.yaml.tpl`. Instead, configure Cilium's `ipam.mode: cluster-pool` explicitly in `config/cilium-values.yaml.tpl`, with the pool CIDR and per-node mask size defined once in `config/cluster.env` (`CILIUM_CLUSTER_POOL_CIDR`, `CILIUM_CLUSTER_POOL_MASK_SIZE`).

**Alternatives considered:**
- Set `podSubnet` anyway "for clarity/consistency with other CNI tutorials" — rejected: it would be silently ignored by Cilium's cluster-pool IPAM, creating a config value that looks load-bearing but isn't, which is worse for a teaching-oriented repository than omitting it with an explanation.
- Use Cilium's `kubernetes` IPAM mode (which *does* consume kube-controller-manager's node-CIDR allocation) instead of `cluster-pool` — rejected: `cluster-pool` is Cilium's own documented default and recommended mode outside of specific migration scenarios; there was no reason to deviate from it just to make `podSubnet` meaningful.

**Consequences:** Anyone reading `kubeadm-config.yaml.tpl` who expects to find a `podSubnet` (as in most generic kubeadm tutorials) needs this ADR or the template's own comment to understand why it's absent — addressed by an explicit comment in the template itself pointing here.

**Risks:** Low — this is Cilium's own documented default behavior, not a workaround.

**Validation requirements:** Confirm pod IPs assigned cluster-wide fall within `CILIUM_CLUSTER_POOL_CIDR` and that each node's allocated per-node CIDR is exactly `/${CILIUM_CLUSTER_POOL_MASK_SIZE}` in size, once the cluster is actually provisioned.

## ADR-012: Rancher local-path-provisioner as the lab StorageClass

**Status:** Accepted

**Context:** `auto-setup-default-kube-env` needs a dynamic `StorageClass` so downstream labs (Prometheus/Loki/Jaeger storage, demo workload PVCs) don't each have to solve storage provisioning themselves, but this is a disposable, single-host lab, not a platform that needs to demonstrate production-grade storage architecture.

**Decision:** Install [Rancher local-path-provisioner](https://github.com/rancher/local-path-provisioner) as the sole storage provisioner, exposed as the `local-path` StorageClass and set as the cluster default.

**Alternatives considered:**
- Longhorn — rejected: adds real operational weight (its own controller/manager/engine pods, replication configuration, a whole additional learning surface) that this tool-neutral base-platform module has no business introducing, especially given this repository already has five other tools' worth of learning surface ahead of it.
- Raw `hostPath` volumes, no provisioner at all — rejected: no dynamic provisioning means every downstream lab would need to hand-author a `PersistentVolume` per `PersistentVolumeClaim`, pushing storage-plumbing work onto every module instead of solving it once here.
- A cloud-provider-style CSI driver — not applicable: this is a local VirtualBox lab with no cloud storage API to back one.

**Consequences:** Every downstream lab gets a working dynamic `StorageClass` "for free," at the cost of the explicit limitations documented in `auto-setup-default-kube-env/docs/STORAGE.md`: no HA, node-pinned data (a `PersistentVolume`'s data lives on whichever single node's disk it was first provisioned on), and total data loss if that node's VM is destroyed.

**Risks:** A downstream lab that doesn't read `docs/STORAGE.md` first could be surprised by node-affinity-driven scheduling constraints on a StatefulSet using this storage. Documented explicitly to mitigate.

**Validation requirements:** `auto-setup-default-kube-env/tests/storage-test.sh` — create PVC, create pod, write data, read data, restart pod, confirm persistence, clean up — must pass before this module's Definition of Done is met.
