# Kyverno-Istio-Opentelementry

A phased, hands-on Kubernetes platform-engineering lab covering **policy enforcement (Kyverno)**, **service mesh (Istio)**, and **observability (OpenTelemetry, Prometheus, Grafana, Jaeger, Loki)** — built on a reusable, tool-neutral Kubernetes foundation provisioned with VirtualBox and Vagrant, using Cilium as the CNI.

This repository is written for engineers who are already fluent in Linux, Kubernetes, containers, CI/CD, and production operations, but who want a deep, from-first-principles treatment of distributed tracing, trace propagation, log pipelines, and modern service-mesh/policy tooling — not a "click here" tutorial.

## Repository status

> **This project is implemented phase by phase.** Each module is built, validated, and documented independently before the next phase begins. See [`PROJECT-IMPLEMENTATION-PLAN.md`](PROJECT-IMPLEMENTATION-PLAN.md) for the authoritative phase list and current progress, and [`docs/VALIDATION-STATUS.md`](docs/VALIDATION-STATUS.md) for what has actually been built and tested so far.
>
> **Current state: Phase 5 in progress (partial).** `auto-setup-default-kube-env/` (base platform), `kyverno/` (independent policy lab), `istio/` (independent service-mesh lab, sidecar mode, Cilium CNI-chained), and `opentelemetry-prometheus-grafana-jaeger-loki/` (independent observability lab) are all fully built and statically validated, but none has been run against a live cluster in this repository yet; see [`docs/VALIDATION-STATUS.md`](docs/VALIDATION-STATUS.md) for exactly what that means and the commands to complete it. The final all-tools integrated lab has not been started.

## High-level architecture

The repository has one reusable platform layer and four tool layers. The tool layers are independent of each other; only the final integrated lab depends on artifacts from the others.

```text
auto-setup-default-kube-env   (reusable Kubernetes platform: VirtualBox + Vagrant + Cilium)
        │
        ├──> kyverno                                     (independent policy lab)
        ├──> istio                                       (independent service-mesh lab)
        ├──> opentelemetry-prometheus-grafana-jaeger-loki (independent observability lab)
        └──> all-tools-integrated-lab                     (integrates the above, reuses tested artifacts)
```

Full diagrams and reasoning are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Module overview

| Module | Owns | Status |
| --- | --- | --- |
| [`auto-setup-default-kube-env/`](auto-setup-default-kube-env/) | Reusable 3-node Kubernetes platform: VirtualBox/Vagrant VMs, containerd, kubeadm, Cilium CNI + Hubble, Helm, local StorageClass, kubeconfig export, validation and rebuild automation | Built, statically validated — live-cluster run pending |
| [`kyverno/`](kyverno/) | Independent Kyverno policy-engine lab: validate/mutate/generate/cleanup/verifyImages policies, policy exceptions, policy reports, audit vs. enforce | Built, statically validated — live-cluster run pending |
| [`istio/`](istio/) | Independent Istio service-mesh lab (sidecar mode, Istio CNI plugin chained with Cilium): traffic management, mTLS, authorization, JWT, egress control, resilience patterns | Built, statically validated — live-cluster run pending |
| [`opentelemetry-prometheus-grafana-jaeger-loki/`](opentelemetry-prometheus-grafana-jaeger-loki/) | Independent observability lab: OpenTelemetry Collector (Agent+Gateway)/Operator, metrics → Prometheus, traces → Jaeger, logs → Loki via the `filelog` receiver, all visualized in Grafana, against a custom two-language demo app | Built, statically validated — live-cluster run pending |
| [`all-tools-integrated-lab/`](all-tools-integrated-lab/) | Final integrated lab combining Cilium, Kyverno, Istio, and the full observability stack against instrumented demo services and production-style failure scenarios | Planned |

## Recommended learning order

1. **`auto-setup-default-kube-env/`** — stand up the reusable Kubernetes foundation once; validate Cilium and Hubble.
2. **`kyverno/`** — run the policy lab in isolation, then clean it up.
3. **`istio/`** — run the service-mesh lab in isolation, then clean it up.
4. **`opentelemetry-prometheus-grafana-jaeger-loki/`** — run the observability lab in isolation, then clean it up.
5. **`all-tools-integrated-lab/`** — reset or rebuild the base cluster, then run everything together.

Each independent lab is designed to be installed and fully removed without touching the others. The exact sequencing, including when to reuse a cluster versus rebuild it, is documented in [`docs/LAB-WORKFLOW.md`](docs/LAB-WORKFLOW.md).

## Base environment overview

A 3-node cluster (`otel-control-plane`, `otel-worker-1`, `otel-worker-2`) provisioned with Vagrant + VirtualBox on Ubuntu Server LTS, using containerd as the container runtime, kubeadm for cluster bootstrap, and Cilium as the primary CNI with Hubble enabled for network observability. `kube-proxy` is retained initially; a Cilium kube-proxy-replacement profile is documented as an advanced, later option. Full topology, IP plan, and resource profiles are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/VERSIONS.md`](docs/VERSIONS.md).

## Independent lab model

Every tool lab (`kyverno/`, `istio/`, `opentelemetry-prometheus-grafana-jaeger-loki/`) is self-contained: it installs only its own tooling on top of the shared base cluster, is independently validated, and is independently removable via its own cleanup automation. No independent lab depends on any other independent lab or on the integrated lab. This keeps each lab safe to learn, break, and reset without collateral effects on the others. Rationale is recorded in [`docs/DECISIONS.md`](docs/DECISIONS.md) (ADR-004).

## Integrated lab overview

`all-tools-integrated-lab/` combines Cilium networking, Kyverno policy enforcement, Istio service mesh, and the full OpenTelemetry/Prometheus/Grafana/Jaeger/Loki observability stack against a shared set of instrumented microservices, including production-style failure injection. It reuses configuration and manifests already validated in the independent labs rather than re-deriving them.

## Prerequisite summary

A full prerequisite list will accompany each module as it is implemented. At a minimum, expect to need:

- A host with virtualization support and either the **minimum** (~16 GB RAM) or **recommended** (~32 GB RAM) resource profile documented in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- VirtualBox and Vagrant
- `kubectl`, `helm`, and standard Linux/container tooling
- Familiarity with Kubernetes operations; OpenTelemetry, Istio, Kyverno, and Cilium concepts are taught in-repo rather than assumed

## Repository documentation

| Document | Purpose |
| --- | --- |
| [`PROJECT-IMPLEMENTATION-PLAN.md`](PROJECT-IMPLEMENTATION-PLAN.md) | Phase-by-phase implementation plan with definition of done per phase |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System architecture, diagrams, and design rationale |
| [`docs/REPOSITORY-GOVERNANCE.md`](docs/REPOSITORY-GOVERNANCE.md) | Naming, scripting, security, and contribution conventions |
| [`docs/VERSIONS.md`](docs/VERSIONS.md) | Planned component version matrix |
| [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md) | Cross-component compatibility and conflict matrix |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | Architecture decision records |
| [`docs/LAB-WORKFLOW.md`](docs/LAB-WORKFLOW.md) | Planned end-to-end lab execution sequence |
| [`docs/VALIDATION-STATUS.md`](docs/VALIDATION-STATUS.md) | What has actually been built and validated, by phase |
