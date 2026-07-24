# Lab 14: Metrics Exemplars

## Objective

Click an exemplar dot on a Prometheus histogram panel in Grafana and confirm it opens the exact trace that produced it.

## Concepts exercised

`docs/08-telemetry-correlation.md`'s metric→trace correlation, `docs/05-metrics.md`'s exemplar mechanics.

## Prerequisites

Labs 08/09, 11 complete.

## Steps

1. **Confirm exemplar storage is enabled**:
   ```bash
   kubectl -n observability exec deploy/kube-prometheus-stack-prometheus -c prometheus -- cat /etc/prometheus/config_out/prometheus.env.yaml 2>/dev/null | grep -i exemplar || \
   kubectl -n observability get prometheus -o jsonpath='{.items[0].spec.enableFeatures}'
   ```
   Expect `exemplar-storage` present.

2. **Generate load specifically against `order_processing_duration`** (already emitted on every order):
   ```bash
   make generate-load ARGS="100 10 30"
   ```

3. **Query for exemplars directly via the API**:
   ```bash
   make port-forward-prometheus &
   curl -s -G http://localhost:9090/api/v1/query_exemplars \
     --data-urlencode 'query=order_processing_duration_bucket' \
     --data-urlencode "start=$(date -d '5 minutes ago' +%s)" \
     --data-urlencode "end=$(date +%s)" | python3 -m json.tool
   ```
   Confirm at least one exemplar with a `trace_id` label.

4. **In Grafana**: open the Application Overview dashboard's "P50/P95/P99 latency" panel, enable "Exemplars" in the panel's display options if not already on, look for small diamond markers on the graph — click one.

5. **Confirm it opens the corresponding trace in Jaeger** (via the `exemplarTraceIdDestinations` link), and that the trace's duration is consistent with the histogram bucket the exemplar came from.

## Validation

Step 3's API query returns at least one exemplar; step 5's click-through opens a real, matching trace.

## Failure scenarios to notice

Query `http_server_duration_milliseconds_bucket` (the framework-auto-generated histogram, not the custom `order_processing_duration`) for exemplars — depending on the auto-instrumentation library version, this may or may not attach exemplars as reliably as the manually-instrumented `order_processing_duration` does; compare the two and note any difference — a real-world reminder that exemplar support can vary by instrumentation library, not just by whether the feature flag is on.

## Cleanup

None.

## Reflection

Exemplars require BOTH Prometheus's `exemplar-storage` feature flag AND the SDK attaching one at record-time. If only one of the two were true, what would you actually observe — an error, or just silently no exemplars? Trace through what you'd check to tell the difference (`docs/21-troubleshooting.md` "Exemplar links missing").
