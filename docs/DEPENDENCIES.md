# Dependency and Compatibility Matrix

This document records cross-component dependencies, required cluster resources, and known or plausible conflicts. It complements [`VERSIONS.md`](VERSIONS.md) (which pins exact planned versions) and [`ARCHITECTURE.md`](ARCHITECTURE.md) (which explains the diagrams these dependencies support). Nothing here has been validated against a running cluster yet — see [`VALIDATION-STATUS.md`](VALIDATION-STATUS.md).

## 1. Kubernetes and Cilium

- **Dependency direction:** Cilium is installed as the CNI immediately after `kubeadm init`/`kubeadm join`, before any workload other than core `kube-system` components is scheduled. Nodes stay `NotReady` until a CNI is present.
- **Compatibility:** Cilium 1.19.x is e2e-tested against Kubernetes 1.32–1.35, which covers the planned Kubernetes 1.35.6 base (see [`VERSIONS.md`](VERSIONS.md#cross-cutting-compatibility-decision)).
- **kube-proxy interaction:** kube-proxy is retained initially (ADR-003), so Cilium runs in a mode that coexists with kube-proxy rather than replacing it. A future advanced profile documents full kube-proxy replacement (`kubeProxyReplacement=true`), which changes how `kube-apiserver` reachability and service routing work and must not be silently mixed with the default profile.
- **Ordering requirement:** Cilium must be installed before Hubble is enabled, and before any other component that relies on pod networking (Kyverno, Istio, OTel Collector DaemonSets) is deployed.

## 2. Kubernetes and Kyverno

- **Compatibility:** Kyverno 1.18.x officially supports Kubernetes 1.33–1.35 — inside the planned 1.35.6 base.
- **Cluster-wide webhooks:** Kyverno registers `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` resources cluster-wide (or scoped via `webhookConfiguration` settings). A misconfigured or unavailable Kyverno controller can block admission for **all** namespaces it watches, including `kube-system` if not explicitly excluded — this is a known failure mode to guard against with `failurePolicy: Ignore` during initial rollout and explicit namespace exclusions for `kube-system`/`kyverno` itself.
- **CRDs required:** `ClusterPolicy`, `Policy`, `PolicyException`, `CleanupPolicy`, `ClusterCleanupPolicy`, `AdmissionReport`/`ClusterAdmissionReport`, plus the newer CEL-based `ValidatingPolicy`/`ImageValidatingPolicy`/`GeneratingPolicy` types introduced as stable in 1.17+.
- **Ordering requirement:** Install Kyverno after Cilium (needs pod networking for its own webhook pods to become reachable) but independently of Istio and the observability stack — no dependency either direction.

## 3. Kubernetes and Istio

- **Compatibility:** Istio 1.30.x supports Kubernetes 1.32–1.36 — inside the planned 1.35.6 base, with headroom for a later Kubernetes minor bump.
- **Cluster-wide webhooks:** Istio's sidecar injector is a `MutatingWebhookConfiguration` scoped by namespace label (`istio-injection=enabled`); unlike Kyverno's default cluster-wide watch, Istio injection is opt-in per namespace, which limits blast radius but means injection must be explicitly enabled on every namespace that needs a mesh sidecar (including `demo`/`integrated-demo`).
- **CRDs required:** `VirtualService`, `DestinationRule`, `Gateway`, `ServiceEntry`, `PeerAuthentication`, `AuthorizationPolicy`, `WorkloadEntry`, `EnvoyFilter`, plus Istio's own CRD group (`networking.istio.io`, `security.istio.io`).
- **Ordering requirement:** Install after Cilium (mesh sidecars need pod networking); independent of Kyverno and observability.

## 4. Kubernetes and the OpenTelemetry Operator

- **Compatibility:** No published Kubernetes floor/ceiling beyond a generally current supported minor; this is expected to be compatible with 1.35.6, but the exact Operator patch tag is flagged unverified in [`VERSIONS.md`](VERSIONS.md) and must be re-confirmed before Phase 5.
- **CRDs required:** `OpenTelemetryCollector`, `Instrumentation`, `OpAMPBridge` (if used), `TargetAllocator` (if Prometheus service-discovery target allocation is used).
- **Cluster-wide webhook:** The Operator's pod-mutating webhook (for auto-instrumentation injection via the `Instrumentation` CRD) is namespace/pod-label-scoped, similar in blast-radius shape to Istio's injector, not Kyverno's default cluster-wide watch.
- **Ordering requirement:** Install after Cilium; independent of Kyverno and Istio, though in the integrated lab it must coexist with both webhook types on the same pods (see §9 below).

## 5. OpenTelemetry Collector and Loki OTLP ingestion

- Loki natively ingests OTLP logs over HTTP at the `/otlp` endpoint; no separate log-shipping agent or Promtail-style client is required.
- Structured metadata, which OTLP resource/log attributes rely on, is enabled by default from Loki 3.0 onward — the planned Loki 3.7.3 satisfies this.
- The Collector Gateway's Loki exporter must target the `/otlp` path specifically (not Loki's legacy push API path), and the `k8sattributes` processor must run **before** the Loki exporter in the pipeline so that Kubernetes metadata is present as structured metadata on arrival.

## 6. Grafana and data sources

- Grafana 13.1.1 is expected to support Prometheus, Loki, and Jaeger as native data-source types; each must be individually configured (URL, auth) and is not auto-discovered.
- Trace-to-log and log-to-trace correlation (Grafana's "derived fields"/"trace to logs" data-source linking) requires consistent trace ID propagation into log records, which depends on the `filelog` pipeline preserving or the application emitting a trace ID field the correlation config can match on — this is a Phase 5 configuration detail, not automatic.
- Metrics exemplars (Prometheus → Jaeger trace links from a metric data point) require the application/SDK to attach exemplars with trace context when recording metrics, and Prometheus's exemplar storage to be enabled.

## 7. Jaeger ingestion protocol

- Jaeger v2 is OTLP-native (built on the OpenTelemetry Collector core) — the Collector Gateway exports directly via OTLP to Jaeger v2's OTLP receiver, with no Jaeger-proprietary protocol (`jaeger.thrift`, `jaeger.proto` over the legacy collector API) required for this repository's pipeline.
- Do not deploy Jaeger v1 components; the two major versions are not designed to be mixed in one pipeline for this lab.

## 8. Cilium and Istio compatibility

- Cilium and Istio can coexist: Cilium provides the CNI/eBPF datapath and NetworkPolicy enforcement at L3/L4, while Istio's sidecars provide L7 traffic management, mTLS, and authorization on top. They are not mutually exclusive and this repository runs them together only in the integrated lab.
- **Known area of friction:** Istio sidecar mode relies on iptables (or, in some configurations, a CNI plugin) to redirect pod traffic into the Envoy proxy. When Cilium is also managing pod networking, both are intercepting/redirecting traffic on the same pods. This must be validated explicitly in the integrated lab (Phase 6) rather than assumed to "just work" — the Istio CNI plugin mode (as opposed to the init-container iptables approach) is the safer default when Cilium is present, since it avoids double-managing iptables rules.
- This is called out as a specific integrated-lab risk in [`PROJECT-IMPLEMENTATION-PLAN.md`](../PROJECT-IMPLEMENTATION-PLAN.md).

## 9. Cilium NetworkPolicy and Istio traffic considerations

- `CiliumNetworkPolicy`/`CiliumClusterwideNetworkPolicy` operate at L3/L4 (and L7 for a limited set of protocols via Envoy-in-Cilium); Istio `AuthorizationPolicy` operates at L7 via the mesh sidecar. In the integrated lab, both policy layers can independently allow or deny the same traffic — a request can be blocked by a `CiliumNetworkPolicy` before it ever reaches the Istio sidecar, or allowed at L3/L4 by Cilium but still denied at L7 by Istio.
- Troubleshooting connectivity issues in the integrated lab therefore requires checking both layers (Hubble flow logs for L3/L4 drops, Istio/Envoy access logs for L7 denials) rather than assuming a single policy engine is responsible.
- Kyverno policies can additionally block the *creation* of NetworkPolicy or Istio custom resources themselves (e.g., a Kyverno policy requiring `PeerAuthentication` to be `STRICT`), which is a third, admission-time layer distinct from the two runtime enforcement layers above.

## 10. Hubble and Prometheus integration

- Hubble (via the Cilium agent and Hubble Relay) can expose flow and network policy metrics in Prometheus-scrape format (`hubble-metrics` on the Cilium agent, typically port `9965`, and Relay's own metrics endpoint).
- This is a separate metrics path from the OpenTelemetry pipeline described in `ARCHITECTURE.md` §6 — Hubble metrics are scraped directly by Prometheus, not routed through the OTel Collector, unless a Prometheus-receiver-in-Collector scrape config is explicitly added later. Treat these as two distinct metrics sources feeding the same Prometheus/Grafana backend, not one unified pipeline, unless and until that integration is explicitly built and documented.

## 11. Storage requirements

| Component | Storage need | Notes |
| --- | --- | --- |
| Prometheus | Persistent volume for TSDB | Retention window must be sized to the lab profile (short retention on the minimum profile) |
| Loki | Persistent volume (or object storage) for chunks + index | Filesystem storage is adequate for lab use; not representative of a production object-storage deployment |
| Jaeger v2 | Storage backend (in-memory for quick labs; a persistent backend for anything longer-lived) | In-memory storage loses all trace data on pod restart — acceptable for short demos, explicitly called out as a limitation |
| Grafana | Small persistent volume for its own SQLite/dashboard state, unless dashboards are fully provisioned as code | Provisioning-as-code is preferred so Grafana state is reproducible |
| Local lab StorageClass | Provided by `auto-setup-default-kube-env/` | All of the above PVCs are expected to bind against this StorageClass; no cloud-provider storage integration is in scope |

## 12. Required Kubernetes CRDs (cumulative, integrated lab)

`ClusterPolicy`, `Policy`, `PolicyException`, `CleanupPolicy`/`ClusterCleanupPolicy`, `ValidatingPolicy`/`ImageValidatingPolicy`/`GeneratingPolicy` (Kyverno) · `VirtualService`, `DestinationRule`, `Gateway`, `ServiceEntry`, `PeerAuthentication`, `AuthorizationPolicy`, `WorkloadEntry`, `EnvoyFilter` (Istio) · `OpenTelemetryCollector`, `Instrumentation`, `TargetAllocator` (OpenTelemetry Operator) · `CiliumNetworkPolicy`, `CiliumClusterwideNetworkPolicy`, `CiliumIdentity`, `CiliumEndpoint` (Cilium) · Prometheus/Grafana/Loki chart-specific CRDs only if the chosen Helm charts include CRD-based operators (to be confirmed per chart choice in Phase 5).

## 13. Cluster-wide webhooks (cumulative, integrated lab)

| Webhook owner | Scope | Failure-mode risk |
| --- | --- | --- |
| Kyverno | Cluster-wide by default (namespace-excludable) | Highest blast radius if the controller is unavailable — must exclude `kube-system` and `kyverno` namespaces |
| Istio sidecar injector | Namespace-label-scoped (`istio-injection=enabled`) | Limited to labeled namespaces |
| OTel Operator instrumentation injector | Namespace/pod-label-scoped | Limited to labeled namespaces/pods |

Running all three simultaneously in the integrated lab means a single pod create can pass through up to three mutating/validating webhook chains; webhook timeout and failure-policy settings for each must be reviewed together, not independently, before Phase 6.

## 14. Port requirements (indicative, to be confirmed per Helm chart during install)

| Component | Port(s) | Purpose |
| --- | --- | --- |
| kube-apiserver | 6443 | Kubernetes API |
| Cilium health/metrics | 4240, 9962–9965 | Health checks, Prometheus metrics |
| Hubble Relay | 4245 | gRPC flow API |
| Hubble UI | 12000 | Web UI |
| Istio control plane (istiod) | 15010–15014 | xDS, webhook, debug |
| Istio ingress gateway | 80, 443, 15021 | Ingress traffic, status |
| OTel Collector | 4317 (OTLP gRPC), 4318 (OTLP HTTP) | Telemetry ingestion |
| Prometheus | 9090 | Query UI/API |
| Grafana | 3000 | Web UI |
| Jaeger v2 (OTLP receiver) | 4317/4318 (shared OTLP ports on the Jaeger pod) | Trace ingestion |
| Loki | 3100 | HTTP API / OTLP `/otlp` |

## 15. Namespace requirements

See the namespace ownership table in [`ARCHITECTURE.md`](ARCHITECTURE.md#planned-namespace-strategy). No namespace is created in this phase.

## Potential conflicts and ordering requirements — summary

1. **CNI must exist before any other workload** — always install/validate Cilium (and Hubble) first.
2. **Kyverno's default cluster-wide webhook can block cluster operations if misconfigured** — exclude `kube-system` and the Kyverno namespace itself explicitly.
3. **Istio + Cilium traffic interception must be validated, not assumed** — prefer Istio CNI plugin mode over the iptables init-container approach when Cilium is present.
4. **Multiple policy/enforcement layers (Kyverno admission, Cilium L3/L4, Istio L7) can each independently block the same request** — troubleshooting must check all applicable layers.
5. **Hubble metrics and OpenTelemetry metrics are separate paths into Prometheus** — do not assume they are unified without explicit integration work.
6. **Loki requires the OTLP `/otlp` path, not the legacy push path**, and the `k8sattributes` processor must run before the Loki exporter in the Collector pipeline.
7. **Independent labs must never be installed in a way that assumes another independent lab's CRDs or namespaces already exist** — only the integrated lab is allowed that assumption, and only for artifacts already validated independently.
