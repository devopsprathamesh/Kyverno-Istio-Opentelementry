# Incident Workflow

The required end-to-end workflow, exercised with real commands and real data — not a narrated hypothetical. Run [`../installation/README.md`](../installation/README.md)'s sequence first.

```text
Grafana alert or dashboard detects error-rate increase
        ↓
Prometheus query identifies affected service
        ↓
Metric exemplar opens the related trace
        ↓
Jaeger shows the failed or slow span
        ↓
Trace ID links to matching Loki logs
        ↓
Kubernetes metadata identifies pod and node
        ↓
Root cause is confirmed
```

## Step 0: manufacture a realistic incident

```bash
cd ..   # module root
make inject-errors ARGS="40 apply"     # payment-service starts declining ~40% of authorizations
make generate-load ARGS="200 20 60"
```

## Step 1: Grafana alert or dashboard detects the increase

```bash
make port-forward-prometheus &
```
Open the **Application Overview** dashboard (`combined-observability-lab/dashboards/README.md`). Within a few minutes, the "Error rate (per service)" panel shows `payment-service`'s ratio rising. Separately, confirm the `HighApplicationErrorRate` alert (`prometheus/alerts/observability-alerts.yaml`) is now `pending`/`firing`:
```bash
curl -s http://localhost:9090/api/v1/alerts | python3 -c 'import json,sys; d=json.load(sys.stdin); print([a["labels"]["alertname"] for a in d["data"]["alerts"] if a["state"]!="inactive"])'
```

## Step 2: Prometheus query identifies the affected service

```bash
curl -s 'http://localhost:9090/api/v1/query?query=job:http_error_ratio:ratio5m' | python3 -m json.tool
```
Confirms `payment-service` specifically, not a cluster-wide problem — the **Service Performance** dashboard's `$service` variable, filtered to `payment-service`, shows the same thing visually.

## Step 3: metric exemplar opens the related trace

In the Application Overview dashboard's latency panel (or a payment-specific panel on Service Performance), click an exemplar dot from around the incident window — this opens Jaeger directly on that exact trace (`docs/08-telemetry-correlation.md`'s metric→trace link, `install/grafana/datasources/datasources.yaml`'s `exemplarTraceIdDestinations`).

Scripted equivalent:
```bash
TRACE_ID=$(curl -s -G http://localhost:9090/api/v1/query_exemplars --data-urlencode 'query=order_processing_duration_bucket' --data-urlencode "start=$(date -d '5 minutes ago' +%s)" --data-urlencode "end=$(date +%s)" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"][0]["exemplars"][0]["labels"]["trace_id"] if d["data"] and d["data"][0]["exemplars"] else "")')
echo "${TRACE_ID}"
```

## Step 4: Jaeger shows the failed span

```bash
make port-forward-jaeger &
curl -s "http://localhost:16686/api/traces/${TRACE_ID}" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for span in d["data"][0]["spans"]:
    tags = {t["key"]: t.get("value") for t in span.get("tags",[])}
    if tags.get("error") or tags.get("otel.status_code") == "ERROR":
        print(span["operationName"], "-> ERROR")
'
```
Expect `payment.authorize` to show as the failed span.

## Step 5: trace ID links to matching Loki logs

```bash
make port-forward-loki &
curl -s -G http://localhost:3100/loki/api/v1/query_range --data-urlencode "query={k8s_namespace_name=\"otel-demo\"} | json | trace_id=\"${TRACE_ID}\"" | python3 -m json.tool
```
Expect a log line like `"message": "Payment declined for order", "severity": "ERROR", "order_id": "..."` — the exact structured log `payment-service/app.py` emits on decline.

## Step 6: Kubernetes metadata identifies pod and node

The same log record's labels (from step 5's response) include `k8s_pod_name`/`k8s_namespace_name` — confirm which specific pod/node:
```bash
kubectl -n otel-demo get pods -l app=payment-service -o wide
```

## Step 7: root cause confirmed

```bash
make inject-errors ARGS="0 revert"
```
Root cause: the configured `FAILURE_PERCENT` env var (this lab's deliberate simulation of "a payment provider's decline rate spiked") — in a real incident, this final step is where you'd identify the *actual* underlying cause (a real downstream dependency issue, a code bug, a bad deploy) rather than a lab-injected setting.

## Validation

Every step above used the SAME `trace_id`, extracted once and threaded through every subsequent query — direct proof this workflow isn't six independent checks, but one connected investigation, exactly like `tests/correlation-test.sh` proves for the correlation piece specifically.

## Reflection

This workflow started at a metric (error rate) and worked forward to a root cause via trace→log→Kubernetes metadata. Design the REVERSE workflow on paper: starting from a single alarming log line (say, an unexpected `ERROR` severity log with no known cause), how would you work backward to confirm its blast radius (how many requests were affected, what the aggregate error rate looked like)? Which tool would you start with instead of Prometheus?
