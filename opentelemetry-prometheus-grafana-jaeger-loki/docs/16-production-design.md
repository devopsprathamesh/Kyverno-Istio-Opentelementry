# Production Design

This document consolidates the production gaps referenced throughout `01`–`15` into one place, and states plainly what this lab implements versus what it only documents — the same honesty pattern used by `../../istio/docs/11-production-design.md`.

## Collector scaling

**Agent scaling** — automatic, one per node (DaemonSet), scales with cluster size with zero manual intervention. **Gateway scaling** — `LAB_PROFILE`-driven replica count (`collector/gateway/deployment.yaml`'s `__REPLICA_COUNT__`), Kubernetes Service round-robin load balancing across replicas. **Load balancing** at this lab's scale is "good enough" via plain Service routing; a real production Gateway tier handling tail sampling at scale needs **consistent routing** — every span of one trace routed to the *same* Gateway replica (typically via a dedicated load-balancer exporter using consistent hashing on trace ID) — not implemented here, since a single logical Gateway doesn't need it yet. **Queue sizing**/**resource sizing**/**throughput**/**payload size**/**network bandwidth** — all real capacity-planning inputs covered conceptually in `18-performance-and-capacity.md`, not load-tested in this lab (no load-testing harness — a stated limitation, `README.md` "Known limitations").

## Reliability

**Backend outage** behavior is directly implemented and tested (`tests/resilience-test.sh`): Collector Agent/Gateway keep running, `sending_queue` absorbs failed exports up to its bound, `retry_on_failure` retries with backoff, and `otelcol_exporter_send_failed_*` makes the failure observable rather than silent. **Persistent queue** (surviving a Collector *process* restart, not just absorbing a *backend* outage) is a real Collector Contrib capability (`exporterhelper`'s persistent-queue-via-`file_storage` option) this lab does **not** enable for the Gateway's export queues (only the Agent's filelog checkpoint uses `file_storage`) — a real, stated gap: a Gateway pod restart during a backend outage loses whatever was still queued in memory. **Graceful shutdown** — the Collector's default SIGTERM handling flushes in-flight batches before exiting, within Kubernetes' pod termination grace period; not explicitly tuned in this lab beyond the chart/manifest defaults. **Pod disruption** — no `PodDisruptionBudget` configured for the Gateway (unlike Istio's istiod, `../../istio/install/istiod-values-recommended.yaml`) — a real, stated simplification for this lab's raw-manifest approach (`docs/DECISIONS.md` ADR-029's tradeoff). **Failure domains** — Agent failure is per-node-isolated (one node's Agent going down doesn't affect other nodes' log collection); Gateway failure, without a PDB/anti-affinity, could in principle have all replicas land on one node.

## Prometheus

Covered in `11-prometheus-architecture.md`; this lab's single-replica, filesystem/PVC-only, permissive-discovery configuration is explicitly not HA — **HA pairs** (two independent Prometheus replicas scraping the same targets, deduplicated at query time), **remote write** for long-term storage beyond local retention, and **Alertmanager HA** (this lab's `install/prometheus/values-recommended.yaml` does run 2 Alertmanager replicas as a partial gesture, but Prometheus itself stays single-replica in both profiles) are the real production additions.

## Loki

Covered in `14-loki-architecture.md`; **object storage** (S3/GCS, not this lab's filesystem PVC), **`Distributed` deployment mode** (not `Monolithic`), and **multi-tenancy** are the concrete production gaps.

## Jaeger

Covered in `13-jaeger-architecture.md`; **Elasticsearch/Cassandra storage backend** (not memory/badger) and **separately-scaled collector/query components** (not all-in-one) are the concrete production gaps.

## Grafana

Covered in `12-grafana-architecture.md`; **HA** (requires a shared external database, not this lab's implicit SQLite), **backup**, and **authentication** (SSO/OAuth instead of this lab's single generated-password admin account) are the concrete production gaps. **Dashboard recovery** is already handled correctly by this lab's pattern — dashboards live as JSON in Git (`grafana/dashboards/`), provisioned automatically, not hand-configured through the UI — worth calling out as something this lab does NOT need to change for production.

## Disaster recovery

**Stateless**: the Collector Agent/Gateway (aside from the Agent's filelog checkpoint, which is recoverable-with-duplication-risk if lost, `06-logs.md`), the Operator, Grafana's rendering layer. **Contains persistent data**: Prometheus's TSDB, Loki's chunks, Jaeger's badger storage (recommended profile only) — all PVC-backed in this lab, all lost if the PVC is deleted, none backed up externally by this lab's automation. **Stored in Git**: every Helm values file, every dashboard JSON, every Collector pipeline config, every alert/recording rule — the entire *configuration* is fully recoverable via `make install-all` from a clean cluster; only the *historical telemetry data* itself is not backed up. **What must be backed up** (if you needed telemetry history preserved across a disaster, which this lab's own default posture does not attempt): Prometheus/Loki/Jaeger PVC snapshots, taken externally to this module's own automation. **What can be recreated**: everything else — this is a meaningfully simpler DR story than a stateful production system, worth stating explicitly rather than leaving implied (mirrors `../../istio/docs/13-upgrades-and-disaster-recovery.md`'s equivalent framing for that module).

## How to validate recovery

```bash
make clean && make install-all LAB_PROFILE=recommended && make validate-installation
```
Confirms the entire module rebuilds from Git alone — the actual DR validation this lab's automation supports today (telemetry-data recovery from external PVC snapshots is out of scope for this module's own scripts, since none are taken by default).

## Failure modes

- Assuming "recommended" profile means production-ready — it means "closer to production shape," not production-sized or production-durable; every gap above applies to both profiles.
- Losing queued-but-not-yet-exported telemetry on a Gateway pod restart during a backend outage — a real, current gap (no persistent export queue), not silently glossed over here.

## Production considerations

This entire document *is* the production-considerations reference every other doc points back to.

## Interview-level explanation

*"What would you change about this lab's observability stack before running it in production?"* — A specific, concrete list, all already flagged rather than discovered later: move Prometheus/Loki/Jaeger to real HA/distributed configurations with external object storage where applicable; enable persistent (not just in-memory) export queues on the Gateway; add a `PodDisruptionBudget` and anti-affinity to the Gateway; move Grafana to SSO auth with a real backing database; and — the single most important addition — implement consistent trace-ID-based routing in front of a multi-replica Gateway tier, since tail sampling's correctness depends on every span of one trace reaching the same replica, which plain Service round-robin does not guarantee at that scale.
