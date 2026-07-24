# Lab 19: Cardinality Control

## Objective

Safely demonstrate high-cardinality damage at small, controlled scale — see the series-count explosion directly, in a way that's easy to clean up and never touches production-scale numbers.

## Concepts exercised

`docs/18-performance-and-capacity.md`/`docs/19-cost-optimization.md`'s cardinality guidance, `collector/examples/cardinality-limiting.yaml`.

## Prerequisites

Lab 07 complete.

## Steps

1. **Baseline: count existing series for a well-behaved metric**:
   ```bash
   make port-forward-prometheus &
   curl -s 'http://localhost:9090/api/v1/query?query=count(orders_total)' | python3 -m json.tool
   ```

2. **Send a deliberately high-cardinality metric directly** (bypassing the app, to control exactly what's sent — never do this against a real metric name in a shared cluster):
   ```bash
   kubectl -n opentelemetry port-forward svc/otel-collector-gateway 14318:4318 &
   for i in $(seq 1 30); do
     python3 - "$i" <<'PYEOF'
import json, sys, urllib.request, time
i = sys.argv[1]
payload = {"resourceMetrics": [{"resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "lab19-cardinality-test"}}]},
  "scopeMetrics": [{"metrics": [{"name": "lab19_test_counter", "sum": {"dataPoints": [{
    "attributes": [{"key": "unique_id", "value": {"stringValue": f"id-{i}-{int(time.time()*1000)}"}}],
    "asInt": "1", "timeUnixNano": str(int(time.time()*1e9)), "startTimeUnixNano": str(int(time.time()*1e9))
  }]}, "isMonotonic": True, "aggregationTemporality": 2}]}]}]}
req = urllib.request.Request("http://127.0.0.1:14318/v1/metrics", data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}, method="POST")
urllib.request.urlopen(req, timeout=5)
PYEOF
   done
   ```

3. **Count the resulting series** — every call above used a unique `unique_id` value, so every call created a NEW time series:
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=count(lab19_test_counter)' | python3 -m json.tool
   ```
   Expect close to 30 — one series per unique attribute value, exactly the cardinality-explosion mechanism `docs/05-metrics.md` warns about, at a safe, small, easily-cleaned-up scale.

4. **Apply the cardinality-limiting example** from `collector/examples/cardinality-limiting.yaml` to a copy of `collector/gateway/configmap.yaml`'s metrics pipeline, reapply, repeat step 2 with a different metric name, and confirm the offending attribute is now dropped before it ever creates a new series.

## Validation

Step 3's series count directly demonstrates the mechanism; step 4 demonstrates the mitigation.

## Failure scenarios to notice

This entire lab IS the failure scenario, deliberately, at safe scale — the reflection question below is the actual point.

## Cleanup

```bash
curl -X POST http://localhost:9090/api/v1/admin/tsdb/delete_series -d 'match[]=lab19_test_counter'
```
(Requires Prometheus's admin API enabled — if not, the test series will simply age out per the configured retention window; no manual cleanup is strictly required for a lab-scoped test metric.)

## Reflection

30 unique attribute values created 30 series in a few seconds. Extrapolate: if `order.id` were used as a metric label in a real production system processing thousands of orders per hour, roughly how many series would accumulate per day, and why does that number alone (before even considering query performance) explain why this is treated as a serious operational mistake, not a minor inefficiency?
