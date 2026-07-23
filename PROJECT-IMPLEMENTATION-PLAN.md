# Project Implementation Plan

This is the authoritative phase list for this repository. Each phase is built, validated, and documented before the next begins. Checkboxes are only ever checked for work that has actually been completed and validated — see [`docs/VALIDATION-STATUS.md`](docs/VALIDATION-STATUS.md) for the current evidence behind any checked box.

## Phase 1: Repository architecture and governance

**Objective:** Establish repository structure, architecture documentation, governance conventions, version research, dependency analysis, architecture decisions, lab workflow, and validation-status tracking — with no implementation work.

**Scope:** Root `README.md`, this plan, `docs/ARCHITECTURE.md`, `docs/REPOSITORY-GOVERNANCE.md`, `docs/VERSIONS.md`, `docs/DEPENDENCIES.md`, `docs/DECISIONS.md`, `docs/LAB-WORKFLOW.md`, `docs/VALIDATION-STATUS.md`, root `.gitignore`.

**Files expected:**
- `README.md`, `.gitignore`, `PROJECT-IMPLEMENTATION-PLAN.md` (root)
- `docs/ARCHITECTURE.md`, `docs/REPOSITORY-GOVERNANCE.md`, `docs/VERSIONS.md`, `docs/DEPENDENCIES.md`, `docs/DECISIONS.md`, `docs/LAB-WORKFLOW.md`, `docs/VALIDATION-STATUS.md`

**Dependencies:** None — this is the foundation phase.

**Validation requirements:** All required files exist; no placeholder tokens (`TODO`/`TBD`/`FIXME`/`CHANGEME`/`<repository-url>`); `git diff --check` clean; Mermaid diagrams manually syntax-reviewed (tool-validated if a validator is available); no secret-like files introduced; no nested `.git`.

**Definition of done:**
- [x] Repository inspected (structure, git status, existing file contents read before modification)
- [x] Root README provides navigation to every module and every governance document
- [x] This implementation plan exists with all seven phases defined
- [x] Architecture diagrams exist and are manually syntax-reviewed
- [x] Directory ownership documented
- [x] Version research documented with sources and an explicit research timestamp
- [x] Dependencies and potential conflicts documented
- [x] Architecture decisions (ADR-001–010) recorded
- [x] Lab workflow documented
- [x] Validation status initialized
- [x] `.gitignore` created
- [x] No Kubernetes/tool implementation started

**Known risks:** Version research can go stale quickly given active release cadences (see the uncertain-compatibility flags in `docs/VERSIONS.md`); some items (OTel Operator exact patch, Helm v3-vs-v4 per-chart compatibility) are explicitly flagged for re-verification rather than treated as settled.

**Out of scope:** Any Vagrantfile, kubeadm config, Cilium manifest, Kyverno policy, Istio manifest, OTel Collector config, Prometheus/Grafana/Jaeger/Loki config, demo application code, Kubernetes workload manifests, or CI workflow implementation.

---

## Phase 2: Base VirtualBox and Vagrant Kubernetes environment

**Objective:** Provision the reusable, tool-neutral 3-node Kubernetes platform described in `docs/ARCHITECTURE.md` §3–4.

**Scope:** `auto-setup-default-kube-env/` — Vagrantfile, per-node provisioning scripts (Ubuntu Server LTS base, containerd, kubeadm bootstrap), Cilium/Hubble install, Helm install, local StorageClass, optional local registry, kubeconfig export, cluster validation script, cleanup/rebuild automation.

**Files expected:** `auto-setup-default-kube-env/Vagrantfile`, provisioning shell scripts (`set -euo pipefail` per governance), Cilium Helm values pinned to the version in `docs/VERSIONS.md`, a `Makefile` implementing the target list in `README.md`, a module-level `README.md` documenting exact steps.

**Dependencies:** Phase 1 documentation (architecture, versions, governance conventions) is the spec this phase implements against.

**Validation requirements:** All three nodes reach `Ready`; `cilium status` reports healthy; `hubble observe` shows flow data; `kubectl` works from the host via the exported kubeconfig; `make destroy && make setup` reproduces the same result (idempotency/rebuild check).

**Definition of done:**
- [x] Vagrantfile defines `otel-control-plane` (192.168.56.10), `otel-worker-1` (192.168.56.11), `otel-worker-2` (192.168.56.12) with explicit ordered provisioning (not implemented: actually booted — see below)
- [x] containerd + kubeadm bootstrap automation written, targeting the pinned Kubernetes version (1.35.6) — not yet run against a live VM
- [x] Cilium + Hubble install automation written per `docs/VERSIONS.md` pinned versions — not yet validated against a live cluster
- [x] Helm install automation written; local StorageClass (local-path-provisioner) install + PVC smoke-test automation written — not yet validated against a live cluster
- [x] Host kubeconfig export automation written — not yet validated against a live cluster
- [x] `make validate`, `make status`, `make rebuild` implemented — not yet run against a live cluster
- [x] No Kyverno/Istio/observability component present anywhere in this module's automation
- [ ] **Live cluster actually provisioned and all of the above validated end to end** — deliberately not done in this session; the user chose "build and statically validate only" for this pass (see `docs/VALIDATION-STATUS.md` Phase 2 detail for the exact reason and the exact commands to complete this)

**Status: automation complete and statically validated; live-cluster runtime validation intentionally deferred to the user.** See `docs/VALIDATION-STATUS.md` for the full breakdown of what was and wasn't checked.

**Known risks:** Kernel/eBPF feature availability on the chosen Ubuntu Server LTS image; static private-IP stability across VM restarts; resource sizing (minimum vs. recommended profile) may need real-world adjustment; this host previously had an unrelated Vagrant/VirtualBox environment claiming the same `192.168.56.10-.12` IPs (resolved by the user destroying it — see `docs/DEPENDENCIES.md`), and `scripts/host/check-prerequisites.sh` now guards against this class of conflict generally; several pinned package/tag details (containerd.io's exact Docker-apt-repo revision suffix, the Hubble CLI's `stable.txt`-resolved version) are resolved dynamically at install time rather than hardcoded, since they were not reliably determinable through static research alone.

**Out of scope:** Any application-layer tool installation (explicitly prohibited from this module's automation, per `docs/ARCHITECTURE.md` §9).

---

## Phase 3: Independent Kyverno lab

**Objective:** Build and validate the standalone Kyverno policy-engine lab.

**Scope:** `kyverno/` — install automation, policy examples across all types (validate/mutate/generate/cleanup/verifyImages), policy exceptions, policy reports, audit-vs-enforce examples, failure scenarios, troubleshooting guide, cleanup automation.

**Files expected:** `kyverno/Makefile`, `kyverno/README.md`, policy manifests organized by type, a demo namespace/workload to exercise policies against, a `docs/` or inline troubleshooting section.

**Dependencies:** Phase 2's validated base cluster. No dependency on Istio or observability modules.

**Validation requirements:** Each policy type demonstrably enforces (or reports on, in audit mode) its intended behavior against a test resource; `make validate` confirms Kyverno controller health and policy report generation; `make uninstall` leaves no residual CRDs/webhooks/namespace.

**Definition of done:**
- [x] Kyverno automation pinned at the version recorded in `docs/VERSIONS.md` (chart 3.8.2 / app v1.18.2) — not yet installed against a live cluster
- [x] At least one working example of each required policy type (17 policies across all 9 `policies/` subdirectories) — statically validated, not yet runtime-validated
- [x] Policy exceptions and policy reports demonstrated in lab documentation and automation — not yet runtime-validated
- [x] Admission vs. background processing and audit vs. enforce mode both documented and both have dedicated labs/policies — not yet runtime-validated
- [x] At least one documented production-style failure scenario and its resolution (`kyverno/docs/14-troubleshooting.md`'s 27-row table, exercised hands-on in `labs/lab-16-troubleshooting.md`)
- [x] `make install`, `make deploy-demo`, `make validate-installation`, `make status`, `make clean`, `make uninstall` implemented per governance conventions (plus the full target list from the phase spec)
- [ ] **Live cluster runtime validation actually performed** — deliberately not done in this session; no live cluster existed at the time (see `docs/VALIDATION-STATUS.md` Phase 3 detail for exact commands to complete this)

**Status: automation and documentation complete and statically validated; live-cluster runtime validation pending (no cluster existed this session, matching this phase's own "no live cluster available" execution policy).** See `docs/VALIDATION-STATUS.md` for the full breakdown.

**Known risks:** Kyverno's default cluster-wide webhook scope requires careful `kube-system`/`kyverno` namespace exclusion (see `docs/DEPENDENCIES.md` §2) to avoid locking out cluster operations during the lab — this lab's `install/values-*.yaml` extend the chart's default `resourceFiltersExcludeNamespaces` accordingly, but this has not yet been runtime-confirmed. Kyverno's exact webhook-configuration and CRD names were not hardcoded where genuinely chart-version-dependent (this lab's automation discovers them by prefix/label rather than exact name — see `kyverno/scripts/lib/kubernetes.sh`), a defensive pattern adopted after the SIGPIPE-under-pipefail lesson from Phase 2. `verifyImages`'s keyless path depends on outbound network access to Sigstore's Rekor, not fully testable in a restricted-network environment (documented in `kyverno/docs/08-image-verification.md`, not hidden).

**Out of scope:** Istio or observability integration (reserved for Phase 6).

---

## Phase 4: Independent Istio lab

**Objective:** Build and validate the standalone Istio service-mesh lab in sidecar mode.

**Scope:** `istio/` — install automation (sidecar mode, Istio CNI plugin preferred per `docs/DEPENDENCIES.md` §8), sidecar injection, Gateway/VirtualService/DestinationRule examples, traffic shifting/canary/retries/timeouts/fault injection/circuit breaking, mTLS/PeerAuthentication/AuthorizationPolicy, ServiceEntry/egress control, troubleshooting, cleanup.

**Files expected:** `istio/Makefile`, `istio/README.md`, `istio/manifests/` (or similar) covering each traffic-management and security feature, a demo multi-service app to route traffic between.

**Dependencies:** Phase 2's validated base cluster. No dependency on Kyverno or observability modules.

**Validation requirements:** Sidecar injection confirmed on the demo namespace; traffic-shifting/canary example demonstrably splits traffic per configured weights; mTLS STRICT mode validated; AuthorizationPolicy denial demonstrated; `make uninstall` leaves no residual CRDs/webhooks/namespace and disables injection.

**Definition of done:**
- [ ] Istio installed (sidecar mode) at the version pinned in `docs/VERSIONS.md`, using the Istio CNI plugin
- [ ] Gateway/VirtualService/DestinationRule traffic-management examples working
- [ ] mTLS, PeerAuthentication, AuthorizationPolicy examples working
- [ ] ServiceEntry/egress control example working
- [ ] `make install`, `make deploy-demo`, `make validate`, `make status`, `make clean`, `make uninstall` implemented per governance conventions

**Known risks:** Istio/Cilium simultaneous traffic interception (`docs/DEPENDENCIES.md` §8) — must be validated even in the independent lab if Cilium NetworkPolicy is exercised here at all; if not exercised here, this risk is deferred to Phase 6.

**Out of scope:** Ambient mode (future advanced lab, per ADR-005); Kyverno or observability integration (reserved for Phase 6).

---

## Phase 5: Independent observability lab

**Objective:** Build and validate the standalone OpenTelemetry/Prometheus/Grafana/Jaeger/Loki observability lab, including the `filelog`-based log pipeline.

**Scope:** `opentelemetry-prometheus-grafana-jaeger-loki/` — OTel Operator, Collector Agent (DaemonSet) + Gateway (Deployment) per `docs/ARCHITECTURE.md` §6–7, auto and manual instrumentation examples, Prometheus, Grafana, Jaeger, Loki, correlation and exemplar configuration, Collector scaling/troubleshooting notes.

**Files expected:** Module `Makefile`/`README.md`, Collector Agent/Gateway configs, `Instrumentation` CRD examples, Helm values for Prometheus/Grafana/Jaeger/Loki pinned per `docs/VERSIONS.md`, Grafana dashboard/datasource provisioning.

**Dependencies:** Phase 2's validated base cluster. No dependency on Kyverno or Istio modules. Must first resolve the OTel Operator exact-version flag in `docs/VERSIONS.md`.

**Validation requirements:** A demo workload's traces, metrics, and logs are all independently confirmed to arrive at their respective backend and be queryable in Grafana; the `filelog` pipeline specifically validated end to end (stdout → node log file → Collector Agent → Gateway → Loki `/otlp` → Grafana LogQL); trace-to-log correlation demonstrated.

**Definition of done:**
- [ ] OTel Operator + Collector (Agent + Gateway) installed at versions confirmed against `docs/VERSIONS.md`
- [ ] Metrics path validated: Collector → Prometheus → Grafana
- [ ] Traces path validated: Collector → Jaeger → Grafana
- [ ] Logs path validated: `filelog` receiver → Collector → Loki `/otlp` → Grafana
- [ ] Trace-to-log and/or log-to-trace correlation demonstrated
- [ ] `make install`, `make deploy-demo`, `make validate`, `make status`, `make clean`, `make uninstall` implemented per governance conventions

**Known risks:** `filelog` receiver behavior on log rotation/high-throughput pods; Collector contrib-component API drift between `v0.x` releases (see `docs/VERSIONS.md`); Loki storage-schema choice needs to be made deliberately, not defaulted.

**Out of scope:** Kyverno or Istio integration (reserved for Phase 6); Hubble-to-Prometheus metrics integration (explicitly noted as a separate, not-yet-built path in `docs/DEPENDENCIES.md` §10).

---

## Phase 6: All-tools integrated lab

**Objective:** Combine Cilium, Kyverno, Istio, and the full observability stack on the base cluster against shared instrumented demo services, including production-style failure scenarios, reusing validated configuration from Phases 3–5.

**Scope:** `all-tools-integrated-lab/` — integration manifests that reference/reuse Phase 3–5 artifacts, shared demo microservices, load-generation and error-injection tooling, combined validation.

**Files expected:** Module `Makefile`/`README.md` explicitly documenting which artifacts are reused from which independent lab; demo microservice manifests instrumented for OpenTelemetry, injected with Istio sidecars, governed by Kyverno policy.

**Dependencies:** Phases 2–5 all validated and complete. Requires a freshly reset or rebuilt cluster per `docs/LAB-WORKFLOW.md` step 9.

**Validation requirements:** All three enforcement/observability layers (Kyverno admission, Istio mesh, Cilium NetworkPolicy) function simultaneously without one silently masking another's effect (per `docs/DEPENDENCIES.md` §8–9); full three-signal observability validated against the mesh-injected, policy-governed demo services; at least one documented failure-injection scenario traced end to end through logs/metrics/traces.

**Definition of done:**
- [ ] Cluster reset/rebuilt to known-clean baseline before integration begins
- [ ] Kyverno, Istio (sidecar), and the observability stack all installed together and individually healthy
- [ ] Cilium/Istio simultaneous traffic interception validated (CNI plugin mode confirmed working, per `docs/DEPENDENCIES.md` §8)
- [ ] At least one multi-layer policy interaction explicitly demonstrated and explained (e.g., a request denied by Cilium NetworkPolicy vs. one denied by Istio AuthorizationPolicy vs. one blocked by Kyverno admission)
- [ ] End-to-end observability (traces/metrics/logs, correlated) validated across the integrated demo services
- [ ] At least one production-style failure scenario documented with its observable signature across logs/metrics/traces
- [ ] `make prerequisites`, `make install`, `make deploy-demo`, `make generate-load`, `make inject-errors`, `make validate`, `make status`, `make clean`, `make uninstall` implemented per governance conventions

**Known risks:** This phase concentrates every risk flagged in Phases 2–5 simultaneously; webhook-chain interactions (`docs/DEPENDENCIES.md` §13) are the most likely source of hard-to-diagnose failures.

**Out of scope:** Any new tool not already covered by Phases 3–5; Istio ambient mode; Cilium kube-proxy replacement (both remain future advanced-lab material).

---

## Phase 7: Repository-wide validation and documentation review

**Objective:** Validate the repository as a whole — cross-module consistency, documentation accuracy against what was actually built, and final governance compliance.

**Scope:** All modules and all `docs/` files; no new tool functionality is added in this phase.

**Files expected:** Updates to `docs/VALIDATION-STATUS.md` reflecting final state; corrections to any documentation found to be inaccurate against the as-built repository; no new module directories.

**Dependencies:** Phases 1–6 complete.

**Validation requirements:** Every module's `make validate` passes from a clean provisioning run; every internal documentation link resolves; every version reference in `docs/VERSIONS.md` matches what was actually installed (or is explicitly reconciled if it drifted); `docs/DECISIONS.md` ADRs reviewed against actual outcomes and amended (new ADR, not silently edited) if reality diverged from the original decision.

**Definition of done:**
- [ ] All module `make validate` targets pass in a single, documented end-to-end run
- [ ] `docs/VALIDATION-STATUS.md` fully reflects actual, current repository state
- [ ] All documentation cross-links verified
- [ ] Any governance violations found (unpinned versions, missing cleanup targets, etc.) resolved or explicitly tracked
- [ ] Repository ready to be presented as a complete, phase-by-phase learning resource

**Known risks:** Documentation drift between what was written during Phases 2–6 and what was actually finally built, if it wasn't updated incrementally along the way.

**Out of scope:** New features or tools beyond what Phases 2–6 defined.
