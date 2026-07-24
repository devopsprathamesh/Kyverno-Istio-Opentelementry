# Lab 05: Loki Only

## Objective

Install Loki and send it a test log line directly via OTLP — no Collector, no filelog, no demo app.

## Concepts exercised

Loki's native OTLP ingestion path, labels vs. structured metadata (`docs/14-loki-architecture.md`).

## Prerequisites

Lab 00 complete.

## Steps

1. **Install Loki**:
   ```bash
   make install-loki LAB_PROFILE=minimum
   make validate-loki
   ```

2. **Send a test log directly**:
   ```bash
   source scripts/lib/common.sh
   source scripts/lib/observability.sh
   kubectl -n observability port-forward svc/loki 13100:3100 &
   send_test_otlp_log 13100 lab05-manual-test "hello from lab 05"
   ```

3. **Query it back**:
   ```bash
   curl -s -G http://localhost:13100/loki/api/v1/query_range \
     --data-urlencode 'query={service_name="lab05-manual-test"}' | python3 -m json.tool
   ```

4. **Check the labels Loki actually indexed** for this stream:
   ```bash
   curl -s http://localhost:13100/loki/api/v1/labels | python3 -m json.tool
   curl -s -G http://localhost:13100/loki/api/v1/label/service_name/values | python3 -m json.tool
   ```

5. **Confirm the OTLP ingestion path specifically** (not the legacy push API):
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:13100/otlp/v1/logs -H 'Content-Type: application/json' -d '{}'
   ```
   Expect a `4xx` (bad request — empty payload) rather than a `404` — confirms the `/otlp/v1/logs` route itself exists and is handled, distinct from a routing failure.

## Validation

```bash
bash tests/loki-test.sh
```

## Failure scenarios to notice

Try sending a log with `send_test_otlp_log` using a `service_name` containing many unique random values in a loop (e.g., a UUID per call) and then check `/loki/api/v1/labels`'s cardinality growing — a hands-on, safe-scale preview of `docs/19-cost-optimization.md`'s cardinality warning, fully explored in `labs/lab-19-cardinality-control.md`.

## Cleanup

```bash
# Ctrl-C the port-forward
```
Leave Loki installed for later labs.

## Reflection

This lab never touched Promtail, and Loki never needed it — where did `service_name` as an indexed label actually come from, given you sent a raw OTLP payload with no explicit Loki-label configuration? (Hint: `scripts/lib/observability.sh`'s `send_test_otlp_log` sets a `service.name` resource attribute — trace how that becomes a Loki label, per `docs/06-logs.md`.)
