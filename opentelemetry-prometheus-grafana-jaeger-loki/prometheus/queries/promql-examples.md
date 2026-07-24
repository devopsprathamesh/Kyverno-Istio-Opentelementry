# PromQL Examples

Copy-pasteable queries, grouped to match [`../../labs/lab-11-metrics-collection.md`](../../labs/lab-11-metrics-collection.md) and the recording rules in [`../recording-rules/observability-recording-rules.yaml`](../recording-rules/observability-recording-rules.yaml) (used interchangeably below — the raw expression is shown first, the recording-rule shortcut noted after).

## Application

```promql
# Request rate, per service
sum(rate(http_server_duration_milliseconds_count{job=~"frontend|order-service|inventory-service|payment-service"}[5m])) by (job)
# recording rule: job:http_requests:rate5m

# Error rate (5xx), per service
sum(rate(http_server_duration_milliseconds_count{job=~"frontend|order-service|inventory-service|payment-service", http_status_code=~"5.."}[5m])) by (job)
# recording rule: job:http_errors:rate5m

# Error ratio (0-1), per service
job:http_errors:rate5m / job:http_requests:rate5m

# P50 latency
histogram_quantile(0.50, sum(rate(http_server_duration_milliseconds_bucket{job=~"frontend|order-service|inventory-service|payment-service"}[5m])) by (job, le))

# P95 latency
histogram_quantile(0.95, sum(rate(http_server_duration_milliseconds_bucket{job=~"frontend|order-service|inventory-service|payment-service"}[5m])) by (job, le))
# recording rule: job:http_request_duration:p95_5m

# P99 latency
histogram_quantile(0.99, sum(rate(http_server_duration_milliseconds_bucket{job=~"frontend|order-service|inventory-service|payment-service"}[5m])) by (job, le))
# recording rule: job:http_request_duration:p99_5m

# Orders per second
sum(rate(orders_total[5m]))
# recording rule: orders:rate5m

# Failed orders per second
sum(rate(orders_failed_total[5m]))
# recording rule: orders_failed:rate5m

# Payment authorization failure rate
sum(rate(payment_failures_total[5m])) / sum(rate(payment_authorizations_total[5m]))
```

## Kubernetes workload (via kube-state-metrics / node-exporter, bundled by kube-prometheus-stack)

```promql
# Pod CPU (cores)
sum(rate(container_cpu_usage_seconds_total{namespace=~"observability|opentelemetry|otel-demo"}[5m])) by (pod)

# Pod memory (bytes)
sum(container_memory_working_set_bytes{namespace=~"observability|opentelemetry|otel-demo"}) by (pod)

# Container restarts (last 1h)
increase(kube_pod_container_status_restarts_total{namespace=~"observability|opentelemetry|otel-demo"}[1h])

# Unavailable replicas per Deployment
kube_deployment_status_replicas_unavailable{namespace=~"observability|opentelemetry|otel-demo"} > 0

# Deployment availability ratio
kube_deployment_status_replicas_available / kube_deployment_spec_replicas
```

## OpenTelemetry Collector internal metrics

All from the Collector's own `/metrics` endpoint (`otelcol_*` — scraped via `../podmonitors/otel-collector-podmonitor.yaml`), covering both the Agent DaemonSet and Gateway Deployment (the `service_instance_id`/pod label distinguishes them).

```promql
# Received telemetry (accepted), by signal
sum(rate(otelcol_receiver_accepted_spans[5m]))
sum(rate(otelcol_receiver_accepted_metric_points[5m]))
sum(rate(otelcol_receiver_accepted_log_records[5m]))

# Exported telemetry (successfully sent), by signal
sum(rate(otelcol_exporter_sent_spans[5m]))
sum(rate(otelcol_exporter_sent_metric_points[5m]))
sum(rate(otelcol_exporter_sent_log_records[5m]))

# Refused telemetry (rejected on receipt — usually memory_limiter under pressure)
sum(rate(otelcol_receiver_refused_spans[5m]))
sum(rate(otelcol_receiver_refused_metric_points[5m]))
sum(rate(otelcol_receiver_refused_log_records[5m]))

# Failed exports (accepted but could not be sent to the backend)
sum(rate(otelcol_exporter_send_failed_spans[5m]))
sum(rate(otelcol_exporter_send_failed_metric_points[5m]))
sum(rate(otelcol_exporter_send_failed_log_records[5m]))

# Sending-queue utilization (0-1) — see docs/09-collector-internals.md "Queue capacity and sizing"
otelcol_exporter_queue_size / otelcol_exporter_queue_capacity

# Collector's own process memory (bytes)
process_runtime_go_mem_heap_alloc_bytes

# Collector's own CPU (seconds/sec)
rate(process_cpu_seconds_total{job=~".*otel-collector.*"}[5m])
```

## Exemplars

Any PromQL query against a histogram bucket metric (e.g. the P95 latency query above) will surface exemplars in Grafana's Explore view or a time-series panel with "Exemplars" toggled on — see `../../install/prometheus/values-*.yaml`'s `enableFeatures: [exemplar-storage]` and `../../install/grafana/datasources/datasources.yaml`'s `exemplarTraceIdDestinations`. No separate PromQL syntax is needed to request exemplars; they ride alongside the sample data Prometheus already stores for that series.
