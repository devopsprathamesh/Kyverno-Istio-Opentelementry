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

## ADR-013: Audit-first policy rollout

**Status:** Accepted

**Context:** `kyverno/` needs a default posture for how every new policy reaches production enforcement. Going straight to `Enforce` risks blocking legitimate workloads on a policy whose real-world blast radius was never measured; staying in `Audit` forever provides no actual protection.

**Decision:** Every policy that has an enforce-mode variant ships with a paired audit-mode file (`kyverno/policies/audit/require-labels-audit.yaml` alongside `kyverno/policies/validate/require-labels-enforce.yaml`), and every lab teaching a validate policy explicitly demonstrates applying Audit first, reviewing `PolicyReport` data, and only then switching to Enforce (`kyverno/labs/lab-02-audit-vs-enforce.md`).

**Alternatives considered:** A single policy file with `validationFailureAction` left as a user-supplied Helm/kustomize parameter — rejected: makes the audit-first *step* optional/skippable rather than a concrete, separately-applied artifact a learner has to consciously replace.

**Consequences:** More policy files to maintain (two per enforced rule instead of one), in exchange for the rollout discipline being structurally encouraged rather than just documented as a recommendation nobody follows under time pressure.

**Risks:** The audit and enforce twins could drift out of sync (different `match`/`pattern` logic) if edited independently without care — mitigated by keeping their rule logic intentionally identical, differing only in `validationFailureAction`, and noting this explicitly in each file's header comment.

**Validation requirements:** `kyverno/tests/cli-test-cases/` test resources apply identically to both twins where relevant, confirming logic parity.

## ADR-014: Namespace exclusion strategy

**Status:** Accepted

**Context:** Every Kyverno policy needs a namespace-exclusion posture. Too broad, and large parts of the cluster go silently unpoliced; too narrow (or none at all), and Kyverno's own namespace or core system namespaces risk being gated by policies never meant for them.

**Decision:** A short, explicit, documented default exclusion list (`kyverno/config/namespaces.env`'s `DEFAULT_EXCLUDED_NAMESPACES`: `kube-system`, `kube-public`, `kube-node-lease`, `kyverno`, `cilium`, `hubble`), applied via the chart's additive `config.resourceFiltersExcludeNamespaces` (not a wholesale replacement of Kyverno's own built-in `resourceFilters` defaults), with `cilium`/`hubble` explicitly documented as currently-no-op entries (Phase 2 installs both into `kube-system`, already covered) rather than silently assumed to matter.

**Alternatives considered:** A wildcard/label-based exclusion (e.g., excluding any namespace labeled `system=true`) — rejected: root `docs/DEPENDENCIES.md`/`kyverno/docs/12-security-and-governance.md` both call out explicitly why open-ended exclusions are a governance risk (any future namespace matching the pattern silently becomes unpoliced with no review).

**Consequences:** Adding a new excluded namespace is a deliberate, reviewable, one-line change to a config file — never an emergent side effect of a label or pattern.

**Risks:** An overly short exclusion list could gate `kube-system`-adjacent operations if a policy's `match` is too broad — mitigated by keeping the default list conservative and requiring every policy to still pass its own narrow `match` review (root `docs/REPOSITORY-GOVERNANCE.md`).

**Validation requirements:** `kyverno/tests/static-validation.sh`'s policy-quality checks confirm no policy uses an unsafe wildcard `kinds` match that would bypass namespace scoping entirely.

## ADR-015: Kyverno CLI for offline policy testing

**Status:** Accepted

**Context:** Waiting for a live cluster to validate every policy edit is slow and, per this phase's own execution constraints, not always even possible (no cluster existed during this phase's implementation).

**Decision:** Every policy in `kyverno/policies/` that can be meaningfully tested offline has a corresponding `kyverno test`-format manifest under `kyverno/tests/cli-test-cases/`, checked into version control, run via `make test-static` — no live cluster required. Cases the CLI cannot fully validate offline (live `context.apiCall` results, real `verifyImages` network verification, real 1-hour-aged `CleanupPolicy` triggers) are explicitly documented as such (`kyverno/tests/static-validation.sh`'s own log output, `kyverno/tests/expected-results.md`), not silently assumed covered.

**Alternatives considered:** Testing policies exclusively against a live cluster — rejected: makes policy correctness feedback slow, and would have been entirely unavailable for this phase's implementation given no cluster existed at the time.

**Consequences:** A meaningful fraction of policy bugs (syntax errors, pattern-logic mistakes) are caught before ever reaching a cluster, at the cost of maintaining a second set of test fixtures alongside the policies themselves.

**Risks:** A false sense of complete coverage if "passed offline" is mistaken for "fully validated" — mitigated by `kyverno/tests/expected-results.md` explicitly distinguishing what each test does and doesn't prove, and every relevant lab pairing an offline test with the corresponding live-cluster runtime test script.

**Validation requirements:** `make test-static` must pass before any policy is considered ready for a live-cluster rollout attempt.

## ADR-016: Safe, narrowly-scoped PolicyExceptions only

**Status:** Accepted

**Context:** `PolicyException` is powerful and easy to misuse — a broadly-scoped exception silently weakens the policy it exempts from for an open-ended set of resources, with no structural signal that it happened.

**Decision:** This lab's one shipped exception (`kyverno/policies/exceptions/allow-demo-hostpath-exception.yaml`) is scoped by exact resource `names` (never a label selector matching an open-ended set), for exactly one rule of exactly one policy, and carries documented (if not Kyverno-enforced) `expires`/`approved-by`/`ticket` annotations. `kyverno/tests/exception-tests.sh` explicitly asserts the negative case: a differently-named resource with the identical pattern is still rejected. Cleanup policies similarly default to namespaced `CleanupPolicy`, never `ClusterCleanupPolicy`, for the same narrow-scoping reasoning.

**Alternatives considered:** Selector-based exceptions for convenience (avoiding a growing `names` list as more resources need the same exemption) — rejected as the default pattern: convenience here directly trades away the auditability that makes exceptions safe to use at all; a growing `names` list is a feature (visible, reviewable growth), not a bug.

**Consequences:** Exceptions require more upkeep (naming each resource explicitly) than a selector would, in exchange for every exception's blast radius being exactly, structurally, what it appears to be.

**Risks:** Kyverno's `PolicyException` CRD has no built-in expiration enforcement — the annotation convention is process, not code, and only as good as whatever external check (not yet built in this repo) enforces it. Documented explicitly as a gap in `kyverno/docs/09-policy-exceptions.md`, not hidden.

**Validation requirements:** `kyverno/tests/exception-tests.sh`'s negative-case assertion must pass for any new exception added to this lab.

## ADR-017: Kyverno and Pod Security Admission responsibility split

**Status:** Accepted

**Context:** Both Kyverno and Pod Security Admission (PSA) can reject a Pod at admission time, and both are present in this repository's target cluster (PSA is part of core Kubernetes since 1.25; Kyverno is this module's install). Without a clear responsibility split, it's unclear which layer "owns" a given rejection, and policies could be written redundantly across both.

**Decision:** PSA is treated as a fast, zero-dependency, coarse-grained floor (its three fixed profiles); Kyverno is treated as the layer for anything organization-specific PSA structurally cannot express (required labels, resource limits, image provenance, generation, exceptions). `kyverno-demo`'s own PSA posture is deliberately set to `privileged` (no PSA restriction) specifically so this lab's Kyverno-focused demonstrations aren't pre-empted by PSA catching the same fixtures first — documented explicitly in `kyverno/demo/namespace.yaml`'s own comment and `kyverno/docs/12-security-and-governance.md`, with `kyverno/labs/lab-05-restrict-privileged-containers.md` step 4 letting a learner directly observe both layers side by side.

**Alternatives considered:** Using Kyverno to fully replace PSA's role, disabling PSA restrictions everywhere — rejected: gives up a free, always-on, non-Kyverno-dependent baseline for no benefit, and couples basic Pod-security hygiene to Kyverno's own availability (docs/11-production-design.md HA concerns).

**Consequences:** A real deployment following this repo's pattern runs both layers together outside this specific demo namespace — PSA `restricted`/`baseline` cluster-wide as a floor, Kyverno for everything else.

**Risks:** A learner could mistakenly assume `kyverno-demo`'s permissive PSA posture is a template for real namespaces — mitigated by the explicit, repeated documentation callouts (README, namespace manifest, docs/12) that it is not.

**Validation requirements:** `kyverno/labs/lab-05-restrict-privileged-containers.md` step 4 must be run at least once to confirm both layers are independently observable, not merely documented.

## ADR-018: `ClusterPolicy`/`Policy` v1 as the primary teaching API over CEL-based policy types

**Status:** Accepted

**Context:** Kyverno 1.17 promoted CEL-based policy types (`ValidatingPolicy`, `ImageValidatingPolicy`, `GeneratingPolicy`, etc.) to GA, and `ClusterPolicy`/`Policy` (the original JMESPath-pattern API) is now formally deprecated, with removal targeted for Kyverno v1.20 (~October 2026) — not yet removed as of the pinned v1.18.2.

**Decision:** `kyverno/policies/` uses `ClusterPolicy`/`Policy` (`kyverno.io/v1`) as the primary teaching vehicle for this entire lab. The CEL-based direction is documented explicitly and accurately (`kyverno/docs/02-architecture-and-internals.md`'s CRD table, `kyverno/docs/04-policy-anatomy.md`'s `cel` section, `kyverno/docs/DECISIONS.md` — this ADR) as the current, real, forward-looking migration path — never hidden or described as removed, since it isn't.

**Alternatives considered:** Building this lab exclusively on the newer CEL-based types, as the more "future-proof" choice — rejected for this lab specifically: nearly every rule-anatomy concept the phase's own requirements call out (`pattern`, `anyPattern`, `deny`, `foreach`, JMESPath, `context`) is `ClusterPolicy`/`Policy`-API surface area, `ClusterPolicy`/`Policy` remains what the overwhelming majority of existing production Kyverno deployments, public examples, and interview contexts use today, and it is still fully functional through the pinned version — a lab teaching only the not-yet-widely-adopted API would be less immediately useful to a learner working with real-world Kyverno clusters right now.

**Consequences:** This lab will need a follow-up pass (out of scope for Phase 3) once `ClusterPolicy`/`Policy` is closer to actual removal (targeted v1.20) to migrate its primary teaching API to the CEL-based types — this is planned obsolescence, acknowledged now rather than discovered later.

**Risks:** A learner using this lab after `ClusterPolicy` removal would need to translate its policies to the CEL-based equivalents — mitigated by the explicit, present-tense documentation of the migration direction throughout, so the eventual transition is not a surprise.

**Validation requirements:** Revisit this ADR's decision explicitly (not silently) once Kyverno v1.20 (or its actual removal timeline) is closer, per root `docs/REPOSITORY-GOVERNANCE.md`'s documentation-currency expectations.
