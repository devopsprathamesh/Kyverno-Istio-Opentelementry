# Performance and Capacity

## Definition

Where telemetry overhead actually comes from in this stack, and the concrete levers this lab exposes (via `LAB_PROFILE`) versus what a real capacity exercise would additionally need.

## Problem solved

Observability itself has a resource cost — every span/metric/log line consumes CPU (instrumentation overhead), memory (SDK batching, Collector queueing), and network bandwidth. Understanding where that cost actually comes from is what separates "the Collector is slow, add more replicas" from correctly diagnosing whether the bottleneck is instrumentation overhead, network, Collector processing, or a downstream backend.

## Traditional implementation

Not applicable — this is a cost/mechanism analysis, not a historical comparison.

## OpenTelemetry implementation: where the cost actually is

**SDK-side overhead** — creating a span/recording a metric is cheap (in-memory operation); the real cost is batching/export, amortized by `BatchSpanProcessor`/`PeriodicExportingMetricReader` (`02-opentelemetry-fundamentals.md`) rather than a synchronous network call per telemetry item. **Network** — OTLP payload size scales with attribute count/cardinality per span/log; this lab's demo app uses a modest, deliberate attribute set (`04-distributed-tracing.md`'s span attribute list), not unbounded per-request metadata. **Collector processing** — `memory_limiter` (bounds the Collector's own memory), `k8sattributes` (a Kubernetes API lookup per unique pod, cached), `tail_sampling` (holds in-flight trace state for `decision_wait`, the single most memory-intensive processor in this pipeline — `09-collector-internals.md`). **Backend ingestion** — Prometheus/Loki/Jaeger each have their own ingestion cost profile, dominated by cardinality (`05-metrics.md`, `14-loki-architecture.md`) more than raw volume.

## Internal processing flow

Not applicable at this conceptual level — see `09-collector-internals.md`'s pipeline diagrams for the actual data flow this cost analysis is describing.

## Kubernetes implementation: this lab's levers

`LAB_PROFILE=minimum` vs. `recommended` (`install/*/values-*.yaml`) is this lab's only implemented capacity lever — resource requests/limits, replica counts, and retention windows, all documented per-component in the relevant architecture doc (`11`–`14`).

## Working configuration

`collector/gateway/configmap.yaml`'s `memory_limiter.limit_mib`/`spike_limit_mib` and `tail_sampling.num_traces` are the two settings most directly trading memory for capacity — read them directly.

## Validation commands

```bash
kubectl -n opentelemetry top pod -l app=otel-collector-gateway
curl -s http://localhost:18888/metrics | grep process_runtime_go_mem_heap_alloc_bytes   # requires make port-forward first
```

## What this lab does NOT measure (a stated gap, not a silent omission)

No load-testing/benchmarking harness is included — `scripts/generate-load.sh` produces bounded, modest traffic for demonstrating labs, not for capacity testing. Real capacity numbers (max sustained throughput per Collector replica, actual P99 export latency under load) are not claimed anywhere in this lab because they were never measured; any specific number would be fabricated. This is the same honesty pattern `../../istio/docs/12-performance-and-capacity.md` uses for the same reason.

## Cardinality, revisited from the capacity angle

Every doc that touches metrics/logs (`05`, `06`, `14`) covers cardinality from the correctness angle; the capacity angle is simpler to state directly: cardinality is usually the dominant cost driver for both Prometheus and Loki, far more than raw event volume — a service emitting 10x the request volume with well-controlled cardinality is usually cheaper to run than one emitting 1x the volume with an unbounded label (`order.id` as a metric label, hypothetically).

## Payload size and network bandwidth

Span/log attribute count and value size directly determine OTLP payload size — this lab's `attributes/redact` processor (`17-security-and-governance.md`) has a secondary, unintended-but-real benefit here: deleting fields also shrinks payloads, though that's not why it exists.

## Failure modes

- Assuming a Collector CPU/memory problem is automatically a "need more replicas" problem — check `docs/09-collector-internals.md`'s pipeline first; a misconfigured `tail_sampling.num_traces` or an unexpectedly high-cardinality attribute reaching `k8sattributes` can dominate resource use regardless of replica count.
- Benchmarking against this lab's `minimum` profile resource requests and extrapolating to production sizing — these numbers were chosen for a homelab, not derived from any load test; see this doc's "What this lab does NOT measure."

## Production considerations

Real capacity planning requires load-testing with production-representative traffic and measuring actual P50/P99 Collector processing latency, actual sustained throughput per replica, and actual backend ingestion headroom — none of which a lab-scale demo app can meaningfully represent. This document states the *mechanisms* of cost, deliberately, rather than fabricating benchmark numbers this lab never measured.

## Interview-level explanation

*"Where does the resource cost of an observability pipeline like this actually come from, and how would you reason about sizing it?"* — Four places, and they have different fixes: SDK-side batching overhead (usually small, already amortized by the batch processor/periodic reader), network bandwidth (scales with attribute count/cardinality per telemetry item, not just volume), Collector processing (memory_limiter bounds the worst case; tail_sampling's in-flight trace state is the single biggest per-Gateway-replica memory cost in this pipeline), and backend ingestion (cardinality-dominated for both Prometheus and Loki). The only way to size any of this correctly is measuring against real, production-representative traffic — this lab deliberately doesn't claim lab-scale numbers generalize, since they were never load-tested to begin with.
