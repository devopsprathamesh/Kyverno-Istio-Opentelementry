# LogQL Examples

Every query below deliberately selects on **indexed labels first** (`k8s_namespace_name`, `service_name`, `k8s_pod_name` — promoted automatically from OTLP resource attributes by Loki's default OTLP-ingestion label mapping) before applying any `| json`/`|=`/regex filtering — see `docs/06-logs.md` "Cardinality control" and `docs/19-cost-optimization.md` for why label selection order matters (Loki has to find the matching streams via labels before it can filter their content; querying by content alone across all streams is far more expensive).

## All logs from one service

```logql
{service_name="order-service"}
```

## Logs from one namespace

```logql
{k8s_namespace_name="otel-demo"}
```

## Logs from one pod

```logql
{k8s_pod_name="order-service-7d8f9c6b5-abcde"}
```

## Error logs

```logql
{service_name="payment-service"} | json | severity="ERROR"
```

## JSON parsing (extract a field for filtering)

```logql
{service_name="order-service"} | json | order_id="order-1a2b3c4d"
```

## Logs for one trace ID (the core of trace-log correlation, `docs/08-telemetry-correlation.md`)

```logql
{k8s_namespace_name="otel-demo"} | json | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"
```

## Logs for one order ID (business-key correlation, cutting across all 4 services)

```logql
{k8s_namespace_name="otel-demo"} | json | order_id="order-1a2b3c4d"
```

## Severity filtering with rate

```logql
sum by (service_name) (rate({k8s_namespace_name="otel-demo"} | json | severity="ERROR" [5m]))
```

## Rate of errors, per service, over time (for a Grafana time-series panel)

```logql
sum by (service_name) (rate({k8s_namespace_name="otel-demo"} | json | __error__="" [5m]))
```

## Top noisy services (highest log volume in the last hour)

```logql
topk(5, sum by (service_name) (count_over_time({k8s_namespace_name="otel-demo"}[1h])))
```

## Multiline stack traces

The `filelog` receiver's `container` operator (`../../collector/agent/configmap.yaml`) already recombines multiline entries (e.g. a Python traceback) into a single log record **before** it ever reaches Loki — so no special LogQL is needed to reassemble them at query time. A single query like:

```logql
{service_name="order-service"} | json | severity="ERROR" |= "Traceback"
```

returns each stack trace as one complete log line, not fragmented across multiple lines — the opposite of what you'd see if multiline recombination were broken (see `docs/21-troubleshooting.md` "Duplicate logs" / a related failure mode where recombination misconfiguration fragments or duplicates entries).

## Avoiding high-cardinality indexed labels

None of the above ever select on `trace_id`, `span_id`, `order_id`, or pod-instance-unique values as **stream labels** — those are queried via `| json` content filtering instead (structured metadata / log-line fields), never promoted to indexed labels. Doing the opposite (indexing `trace_id` as a label) would create a new Loki stream per trace — effectively unbounded cardinality — see `docs/19-cost-optimization.md` and `labs/lab-19-cardinality-control.md`.
