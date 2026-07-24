# Telemetry Correlation

All three correlation links are configured as fields inside [`../../install/grafana/datasources/datasources.yaml`](../../install/grafana/datasources/datasources.yaml) — Grafana doesn't have a separate "correlation" resource for these three; each is a `jsonData` field on the relevant datasource itself. See `docs/08-telemetry-correlation.md` for the full conceptual walkthrough and `labs/lab-13-trace-log-correlation.md`/`labs/lab-14-metric-trace-exemplars.md` for hands-on exercises.

## Metric → trace (Prometheus exemplars)

`datasources.yaml`'s Prometheus entry sets `jsonData.exemplarTraceIdDestinations: [{datasourceUid: jaeger, name: trace_id}]`. Requires: Prometheus's `exemplar-storage` feature flag enabled (`install/prometheus/values-*.yaml`), and the application actually attaching an exemplar with a `trace_id` label when recording a histogram observation — `demo-application/order-service/app.py`'s `order_processing_duration` histogram does this implicitly via the OTel SDK's automatic exemplar attachment from the active span context.

## Trace → log (Jaeger `tracesToLogsV2`)

`datasources.yaml`'s Jaeger entry sets `jsonData.tracesToLogsV2`, querying Loki for `{namespace="otel-demo"} | json | trace_id=\`${__trace.traceId}\`` scoped to the trace's own time range (±1 minute). Clicking "Logs for this span" inside a Jaeger trace view (embedded in Grafana) runs this query.

## Log → trace (Loki `derivedFields`)

`datasources.yaml`'s Loki entry sets `jsonData.derivedFields`, matching the regex `"trace_id"\s*:\s*"([a-f0-9]+)"` against each log line's raw JSON body and linking the captured value as an **internal link** (no `url` field — see the file's own comment) to the Jaeger datasource, which Grafana interprets as "open this trace ID directly."

## Why this works: trace_id has to actually be IN the log line

None of the three links above work unless `trace_id` is genuinely present and correlatable — which is why `collector/agent/configmap.yaml`'s `transform/log_trace_context` processor exists (promoting the JSON-parsed `trace_id` attribute into the OTLP `LogRecord`'s real `trace_id` field) and why `order-service`/`payment-service`'s custom JSON log formatters explicitly include `trace_id`/`span_id` read from the active span. Correlation is a property of the data, not just the Grafana config — see `docs/07-context-propagation.md`.
