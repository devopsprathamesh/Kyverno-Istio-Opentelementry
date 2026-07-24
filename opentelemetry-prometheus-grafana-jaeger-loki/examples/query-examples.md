# Query Examples Index

This module's query references live where they're most useful, alongside the tool they query — this file is the index, not a duplicate:

- **PromQL** — [`../prometheus/queries/promql-examples.md`](../prometheus/queries/promql-examples.md) — request rate, error rate, P50/P95/P99, business metrics, Collector internal metrics, Kubernetes workload metrics.
- **LogQL** — [`../loki/logql/logql-examples.md`](../loki/logql/logql-examples.md) — per-service, per-namespace, per-trace, per-order, severity filtering, cardinality-safe patterns.
- **Jaeger API** — [`../jaeger/queries/jaeger-api-examples.md`](../jaeger/queries/jaeger-api-examples.md) — service/operation/tag/duration search, dependency graph.

## One combined example: the same investigation in all three languages

Find everything related to a specific `order_id`, across all three signals:

```bash
# PromQL — did this order's processing show up in the duration histogram? (no direct per-order query — metrics are aggregated by design, see docs/01-observability-fundamentals.md "Why metrics alone are insufficient")

# LogQL — find every log line mentioning this order
make port-forward-loki &
curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode '{k8s_namespace_name="otel-demo"} | json | order_id="order-1a2b3c4d"' | python3 -m json.tool

# Jaeger API — find the trace(s) tagged with this order
make port-forward-jaeger &
curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=order-service' --data-urlencode 'tags={"order.id":"order-1a2b3c4d"}' | python3 -m json.tool
```

This three-query pattern is directly why `01-observability-fundamentals.md` says metrics alone are insufficient for per-request investigation — only logs and traces can even be asked this specific question; metrics can only answer aggregate questions like "what fraction of orders in the last 5 minutes failed."
