# Lab 11: Metrics Collection

## Objective

Query the demo app's business metrics, confirm recording rules evaluate correctly, and write one new alerting rule yourself.

## Concepts exercised

`docs/05-metrics.md`'s instrument types, `docs/11-prometheus-architecture.md`'s recording/alerting rules.

## Prerequisites

Lab 08 or 09 complete (demo app deployed and has received at least a few requests).

## Steps

1. **Generate some traffic**:
   ```bash
   make generate-load ARGS="50 5 30"
   ```

2. **Query the raw business metrics**:
   ```bash
   make port-forward-prometheus &
   curl -s 'http://localhost:9090/api/v1/query?query=orders_total' | python3 -m json.tool
   curl -s 'http://localhost:9090/api/v1/query?query=order_processing_duration_bucket' | python3 -m json.tool
   ```

3. **Query the recording-rule shortcuts** and confirm they match manual computation:
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=job:http_requests:rate5m' | python3 -m json.tool
   curl -s 'http://localhost:9090/api/v1/query?query=job:http_request_duration:p95_5m' | python3 -m json.tool
   ```

4. **Run every PromQL example** in `prometheus/queries/promql-examples.md`'s "Application" section against your live data.

5. **Write and apply one new alerting rule** — copy the pattern from `prometheus/alerts/observability-alerts.yaml`, add a rule that fires if `orders:rate5m` drops to 0 for 2 minutes while the demo app is supposed to be receiving load (a "no traffic at all" alert, distinct from the existing error-rate/latency alerts):
   ```yaml
   - alert: NoOrdersReceived
     expr: orders:rate5m == 0
     for: 2m
     labels: {severity: warning}
     annotations:
       summary: "No orders processed in the last 5 minutes"
   ```
   Apply it as a new `PrometheusRule` (or add to a copy of the existing file) and confirm it appears in `curl .../api/v1/rules`.

## Validation

```bash
bash tests/metrics-test.sh
```

## Failure scenarios to notice

Query `active_requests` (an UpDownCounter) immediately after a burst of concurrent load, then again 30s later — confirm it returns to near-zero, demonstrating the difference between a Counter (`orders_total`, only ever increases) and an UpDownCounter (goes up and back down) — the wrong instrument type for this metric (a Counter) would never show the "back down" behavior.

## Cleanup

Remove your test `NoOrdersReceived` rule if you don't want it to persist:
```bash
kubectl -n observability delete prometheusrule <your-rule-name>
```

## Reflection

Your new alert in step 5 uses the recording rule `orders:rate5m` rather than re-deriving the raw expression. What's the practical benefit of that choice, beyond just saving a few characters of PromQL?
