# Cost Optimization

## Definition

The concrete levers this lab actually implements (or documents) for keeping an observability stack's storage/compute cost bounded — cardinality control, sampling, retention, and filtering — as distinct from `18-performance-and-capacity.md`'s broader mechanism-level cost analysis.

## Problem solved

Unbounded observability cost is a real, common production failure mode: a well-intentioned "just add more labels/attributes for debuggability" instinct, applied without cardinality discipline, can make a metrics/logging backend's storage bill grow far faster than actual traffic. This lab bakes the countermeasures in from the start rather than retrofitting them after a cost incident.

## Traditional implementation

Reactive cost control — discovering a cardinality explosion or unbounded log volume only after a storage bill spike or a backend falling over, then scrambling to identify and remove the offending label/field after the fact.

## OpenTelemetry implementation: this lab's four levers

**Cardinality control** — `demo-application/*/app.py`'s metric instruments deliberately use only low-cardinality attributes (`status`, `reason`, `customer_type` — never `order.id`); `collector/examples/cardinality-limiting.yaml` shows the processor-level backstop (deleting `order.id`/`customer.id` specifically from the metrics pipeline) for cases where an SDK-level mistake slips through. **Sampling** — tail sampling's probabilistic-baseline policy (`config/lab-settings.env`'s `TAIL_SAMPLING_PROBABILISTIC_PERCENT=15`) means only 15% of normal (non-error, non-slow) traces are stored at all — a direct, deliberate storage-volume reduction, while still guaranteeing the traces most likely to matter (errors, slow requests) are always kept. **Retention** — `config/retention.env`'s profile-scoped windows (Prometheus 6h/24h, Loki 24h/72h) bound storage growth directly; shorter retention is the single most direct cost lever available, traded here against a lab's actual need for historical data (low). **Filtering** — `collector/agent/configmap.yaml`'s `filter/logs` processor drops health-check-probe log noise before it's ever stored — pure volume reduction for data with no diagnostic value.

## Internal processing flow

All four levers operate at different pipeline stages: cardinality control at the SDK (instrumentation choices) and Collector processor level; sampling at the Gateway's `tail_sampling` processor; retention at the backend (Prometheus/Loki config, post-ingestion); filtering at the Collector processor level (pre-ingestion, the cheapest place to drop unwanted data — never pay ingestion/storage cost for data you'll discard anyway).

## Kubernetes implementation

Not Kubernetes-specific — these are pipeline/backend-configuration levers, applicable regardless of the underlying orchestrator.

## Working configuration

`config/retention.env` and `collector/gateway/configmap.yaml`'s `tail_sampling.policies` are the two most consequential cost-control configs in this lab — both already covered in depth elsewhere (`09-collector-internals.md`, `loki/retention/README.md`); this doc's job is naming them explicitly as cost levers, not re-deriving their mechanics.

## Validation commands

```bash
# Confirm the probabilistic-baseline sampling rate is actually producing
# roughly the configured storage-volume reduction:
bash tests/sampling-test.sh
```

## Structured metadata over indexed labels (the Loki-specific cost lever)

Restated from `06-logs.md`/`14-loki-architecture.md` specifically as a cost point: every indexed label multiplies Loki's stream count; every field carried as structured metadata instead does not. `trace_id`/`span_id`/`order_id` as structured metadata (this lab's actual configuration) versus as labels (the mistake `loki/logql/logql-examples.md` explicitly warns against) is potentially the difference between a bounded number of streams and unbounded stream growth.

## Recording rules as a cost lever, not just a convenience

`prometheus/recording-rules/observability-recording-rules.yaml` precomputing `job:http_requests:rate5m` etc. isn't only about query latency (`11-prometheus-architecture.md`) — it also means a dashboard refreshing every 30s re-evaluates one cheap precomputed series instead of the full raw-series aggregation every single refresh, a real, compounding query-compute cost saving at dashboard-refresh scale.

## Failure modes

- Widening tail sampling's probabilistic-baseline percentage "just to see more traces" without considering the direct storage-cost consequence — a real tradeoff, not a free improvement.
- Adding a new high-cardinality metric attribute or Loki label during a debugging session and forgetting to remove it — the single most common real-world cause of an unplanned cardinality/cost incident; worth a habit of reviewing new attributes against `05-metrics.md`/`14-loki-architecture.md`'s cardinality guidance before merging.

## Production considerations

Real production cost optimization typically also includes: tiered/cold storage for older data (not implemented here, since this lab's retention windows are already short), per-team cost attribution (requires the multi-tenancy this lab doesn't implement, `17-security-and-governance.md`), and adaptive/dynamic sampling rates (adjusting the probabilistic-baseline percentage based on current traffic volume rather than a fixed 15%) — all real, documented, none implemented in this lab.

## Interview-level explanation

*"If your observability backend's storage bill suddenly spiked, what would you check first?"* — Cardinality, almost always before volume — a new high-cardinality label or metric attribute (an ID field accidentally promoted to a label, a new span attribute with unbounded values) tends to cause far more storage growth than a proportional traffic increase would. I'd check for new/changed labels on the metrics side and new/changed Loki labels (not structured metadata) on the logs side first, then look at whether retention windows or sampling rates had changed, before assuming the spike is simply "more traffic" — genuine traffic growth is usually the least likely explanation for a sudden, disproportionate cost spike.
