# opentelemetry-prometheus-grafana-jaeger-loki

Independent, production-oriented observability lab: OpenTelemetry Collector (Agent + Gateway), the OpenTelemetry Operator (auto-instrumentation), Prometheus, Grafana, Jaeger, and Loki — installable and removable without touching Kyverno, Istio, or the final all-tools integrated lab.

## 1. Module purpose

Teach the full three-signal observability stack — metrics, traces, logs, and the correlation between them — against a real, custom-built, two-language demo application, from first principles through a production-readiness capstone. See [`docs/01-observability-fundamentals.md`](docs/01-observability-fundamentals.md).

## 2. What OpenTelemetry is

A vendor-neutral API/SDK/Collector/semantic-conventions specification for generating and processing telemetry — see [`docs/02-opentelemetry-fundamentals.md`](docs/02-opentelemetry-fundamentals.md) and [`docs/03-opentelemetry-architecture.md`](docs/03-opentelemetry-architecture.md).

## 3. What Prometheus does

Pull-based metrics storage and query (PromQL), installed via kube-prometheus-stack (bundling the Prometheus Operator, Alertmanager, kube-state-metrics, node-exporter). See [`docs/11-prometheus-architecture.md`](docs/11-prometheus-architecture.md).

## 4. What Grafana does

Visualizes Prometheus/Jaeger/Loki data and wires cross-signal correlation (exemplars, trace-to-log links). **Grafana visualizes; it does not store.** See [`docs/12-grafana-architecture.md`](docs/12-grafana-architecture.md).

## 5. What Jaeger does

Distributed-trace storage and query, via Jaeger v2's native OTLP receiver (no separate agent, no Jaeger-proprietary protocol in this pipeline). See [`docs/13-jaeger-architecture.md`](docs/13-jaeger-architecture.md).

## 6. What Loki does

Label-indexed log storage and query (LogQL), ingesting natively via OTLP — no Promtail, no deprecated Collector `loki` exporter. See [`docs/14-loki-architecture.md`](docs/14-loki-architecture.md).

## 7. Architecture

```text
Metrics → OpenTelemetry Collector → Prometheus → Grafana
Traces  → OpenTelemetry Collector → Jaeger → Grafana
Logs    → OpenTelemetry Collector filelog receiver
        → OpenTelemetry Collector Gateway
        → Loki
        → Grafana
```
Full diagram: [`combined-observability-lab/architecture/README.md`](combined-observability-lab/architecture/README.md). Collector topology: [`docs/10-collector-deployment-patterns.md`](docs/10-collector-deployment-patterns.md).

## 8. Base-cluster prerequisites

This module **never** provisions or destroys Kubernetes, never invokes Vagrant, and never modifies Cilium, kube-proxy, or CoreDNS. It depends entirely on [`../auto-setup-default-kube-env/`](../auto-setup-default-kube-env/) already being up. Every install/runtime target runs `verify-cluster` first (API endpoint `192.168.56.10`, nodes `otel-control-plane`/`otel-worker-1`/`otel-worker-2`, Cilium/kube-proxy/CoreDNS/StorageClass healthy) and refuses on a mismatch.

## 9. Version matrix

| Component | Version | Source |
| --- | --- | --- |
| OpenTelemetry Collector Contrib | `0.157.0` | `open-telemetry/opentelemetry-collector-contrib` releases |
| OpenTelemetry Operator | controller `v0.156.0`, chart `0.120.0` | `open-telemetry/opentelemetry-helm-charts` |
| kube-prometheus-stack | chart `87.19.0` (Prometheus `v3.13.1`, Alertmanager `v0.33.1`) | `prometheus-community/helm-charts` |
| Grafana | app `v13.1.1`, chart `12.8.0` | `grafana-community/helm-charts` (repo migrated — see below) |
| Jaeger | app `v2.20.0`, chart `4.11.1` | `jaegertracing/helm-charts` |
| Loki | chart `18.5.3` (app `3.7.4`) | `grafana-community/helm-charts` |

Full detail, sources, and the **Grafana/Loki chart-repo migration note** (the legacy `grafana.github.io/helm-charts` index is stale for these charts — use `grafana-community.github.io/helm-charts` instead): root [`docs/VERSIONS.md`](../docs/VERSIONS.md) "Phase 5 addendum". Centralized in [`config/versions.env`](config/versions.env).

## 10. Resource profiles

`minimum` (constrained hosts: single replicas, short retention, in-memory Jaeger) vs. `recommended` (~32GB host RAM: 2 Alertmanager replicas, PVC-backed Loki/Jaeger/Prometheus, longer retention). Neither is a full HA configuration — see [`docs/20-high-availability-and-dr.md`](docs/20-high-availability-and-dr.md) for exactly what each profile does and doesn't provide.

## 11. Quick start

```bash
cd ~/github/Kyverno-Istio-Opentelementry/auto-setup-default-kube-env
make setup LAB_PROFILE=recommended
make validate

export KUBECONFIG="$(pwd)/.generated/kubeconfig"

cd ../opentelemetry-prometheus-grafana-jaeger-loki
make prerequisites
make verify-cluster
make install-all LAB_PROFILE=recommended
make validate-installation
make build-demo-images
make deploy-demo
make generate-load
make validate
```

## 12. Independent labs

22 labs, `labs/lab-00-prerequisites.md` through `labs/lab-21-production-readiness.md` — each tool installed and exercised standalone before the pipeline pieces are combined. Full inventory in [`labs/`](labs/); each lab lists its own prerequisites and validation commands.

## 13. Combined lab

[`combined-observability-lab/`](combined-observability-lab/) — every component installed together, exercising the full incident-response workflow (metric alert → exemplar → trace → correlated logs → Kubernetes metadata → root cause) end to end with real commands, not narration.

## 14. Collector architecture

Agent DaemonSet (filelog + local OTLP receiver) + Gateway Deployment (central processing: `k8sattributes`, redaction, tail sampling, fan-out to all 3 backends) — raw manifests, not Operator-managed (`docs/DECISIONS.md` ADR-029). See [`docs/09-collector-internals.md`](docs/09-collector-internals.md) and [`docs/10-collector-deployment-patterns.md`](docs/10-collector-deployment-patterns.md).

## 15. Filelog architecture

`filelog` (Collector Contrib, mandatory, never Promtail) reads `/var/log/pods/*/*/*.log`, parses CRI format + recombines multiline via the `container` operator, enriches with Kubernetes metadata, promotes `trace_id`/`span_id` into real `LogRecord` fields, and exports to Loki's native `/otlp/v1/logs` endpoint. See [`docs/06-logs.md`](docs/06-logs.md).

## 16. Demo application

`frontend` (Node.js, auto-instrumented) → `order-service` (Python, manual) → `{inventory-service` (Python, auto-instrumented)`, payment-service` (Python, manual, configurable latency/failure)`}`. No registry — built locally, imported directly into cluster node containerd (`docs/DECISIONS.md` ADR-030). See [`demo-application/README.md`](demo-application/README.md).

## 17. Accessing UIs

Every backend is `ClusterIP`-only; access via `make port-forward-{prometheus,grafana,jaeger,loki,demo}`, localhost-bound. See [`examples/curl-commands.md`](examples/curl-commands.md).

## 18. Validation

`make test-static` (cluster-free) and `make validate-installation`/`make test-runtime` (live cluster) — see [`tests/expected-results.md`](tests/expected-results.md).

## 19. Queries

[`prometheus/queries/promql-examples.md`](prometheus/queries/promql-examples.md), [`loki/logql/logql-examples.md`](loki/logql/logql-examples.md), [`jaeger/queries/jaeger-api-examples.md`](jaeger/queries/jaeger-api-examples.md), indexed at [`examples/query-examples.md`](examples/query-examples.md).

## 20. Dashboards

5 provisioned dashboards (`grafana/dashboards/`): Application Overview, Service Performance, Kubernetes Workload Overview, OpenTelemetry Collector Health, Logs — auto-provisioned via Grafana's ConfigMap sidecar, no manual UI configuration.

## 21. Alerts

[`prometheus/alerts/observability-alerts.yaml`](prometheus/alerts/observability-alerts.yaml) — high error rate, high P95 latency, service unavailable, Collector failed/refused exports, queue near-full, Collector high memory, Loki ingestion errors, Jaeger unavailable, Prometheus target down, pod restart rate. Every alert carries a `validation` annotation stating exactly how to test-fire it.

## 22. Correlation

Metric exemplar → trace, trace → logs, log → trace — all three wired in [`install/grafana/datasources/datasources.yaml`](install/grafana/datasources/datasources.yaml), proven (not just configured) by [`tests/correlation-test.sh`](tests/correlation-test.sh). See [`docs/08-telemetry-correlation.md`](docs/08-telemetry-correlation.md).

## 23. Troubleshooting

Symptom-first reference covering tracing/metrics/logs/Collector/Operator/infrastructure, plus a triage decision tree: [`docs/21-troubleshooting.md`](docs/21-troubleshooting.md).

## 24. Debug bundle

`make debug-bundle` collects a sanitized troubleshooting archive under `.generated/debug-bundles/` — never Secret contents, passwords, tokens, private keys, or full kubeconfig.

## 25. Cleanup

`make clean-demo` / `make clean-collector` / `make clean-backends` / `make clean` — remove only lab-applied resources; Helm releases untouched.

## 26. Uninstallation

`make uninstall-{prometheus,grafana,jaeger,loki,operator,collector}` / `make uninstall-all` — removes Helm releases in reverse dependency order. CRDs kept by default (`REMOVE_CRDS=true` to also remove them, cluster-wide). **Never** touches Cilium, kube-proxy, or the cluster itself.

## 27. Production considerations

What this lab implements at small scale versus what a real production deployment additionally needs (HA per backend, persistent export queues, object storage for Loki, Elasticsearch/Cassandra for Jaeger, SSO for Grafana) — stated explicitly: [`docs/16-production-design.md`](docs/16-production-design.md) and [`docs/20-high-availability-and-dr.md`](docs/20-high-availability-and-dr.md).

## 28. Known limitations

No load-testing/benchmarking harness (`docs/18-performance-and-capacity.md`); no persistent Gateway export queue (a real, stated gap — `docs/16-production-design.md`); single-tenant Loki/Grafana (`docs/17-security-and-governance.md`); demo app images built locally with no registry, requiring Docker/Podman + Vagrant on whatever host runs `make build-demo-images` (`docs/DECISIONS.md` ADR-030).

## Definition of done

Fully implemented and statically validated (manifests, Collector configs, Python/Node source, Dockerfiles, dashboards). **Runtime validation against a live cluster is pending** — no cluster was available at authoring time; see root [`docs/VALIDATION-STATUS.md`](../docs/VALIDATION-STATUS.md) for the exact commands to run once one exists.

## Next phase

**Phase 6: All-tools integrated Kubernetes lab** — combining Kyverno, Istio, and this observability stack against shared instrumented demo services. Explicitly **not started, not scoped, and not touched** by this module.
