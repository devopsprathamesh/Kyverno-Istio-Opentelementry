# Lab 13: Trace-Log Correlation

## Objective

Navigate from a real trace in Jaeger to its exact matching logs in Loki, and back — both directions, in Grafana's UI and via direct API proof.

## Concepts exercised

`docs/08-telemetry-correlation.md`'s trace↔log correlation.

## Prerequisites

Labs 08/09, 12 complete.

## Steps

1. **Generate a request and find its trace ID**:
   ```bash
   kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/
   make port-forward-jaeger &
   TRACE_ID=$(curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=order-service' --data-urlencode 'limit=1' | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["traceID"])')
   echo "${TRACE_ID}"
   ```

2. **Query Loki directly for that exact trace_id**:
   ```bash
   make port-forward-loki &
   curl -s -G http://localhost:3100/loki/api/v1/query_range \
     --data-urlencode "query={k8s_namespace_name=\"otel-demo\"} | json | trace_id=\"${TRACE_ID}\"" | python3 -m json.tool
   ```
   Confirm at least one log line matches — proof the correlation data itself is real, not just configured.

3. **Now do it in Grafana's UI** — open the trace in Jaeger's Grafana-embedded view (`Explore`, Jaeger datasource, search by trace ID), click "Logs for this span" (the `tracesToLogsV2` link) — confirm it opens Loki, pre-filtered, showing the same log lines.

4. **Now go the other direction** — open the Logs Grafana dashboard, find one of `order-service`'s log lines, click the `TraceID` derived-field link — confirm it opens Jaeger, on the exact trace from step 1.

## Validation

```bash
bash tests/correlation-test.sh
```
This is the strongest proof in the suite — it does exactly what steps 1–2 above do, scripted.

## Failure scenarios to notice

Temporarily comment out `collector/agent/configmap.yaml`'s `transform/log_trace_context` processor from the pipeline (edit a local copy, reapply, restart the Agent), generate a new request, and repeat step 2 for the NEW trace's ID — confirm the log line now has no `trace_id` at all in Loki, even though the application's own JSON log body still contains it as `attributes.trace_id` internally (never promoted to the real `LogRecord.trace_id` field). Restore the processor afterward.

## Cleanup

Restore `collector/agent/configmap.yaml` if you modified it, and `kubectl -n opentelemetry rollout restart daemonset/otel-collector-agent`.

## Reflection

Step 4's failure-scenario variant showed data reaching Loki successfully but failing to correlate. What does that prove about the relationship between "logs are being ingested" and "logs are correlatable" — are they the same guarantee, or two separate ones?
