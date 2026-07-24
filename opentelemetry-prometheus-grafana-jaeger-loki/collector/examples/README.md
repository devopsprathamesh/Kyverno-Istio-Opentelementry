# Collector Configuration Examples

Standalone pipeline-fragment examples referenced by specific labs — not applied by any install script, and not valid complete Collector configs on their own (each is a `processors:`/`exporters:` snippet meant to be read alongside the full pipeline in `../gateway/configmap.yaml` or `../agent/configmap.yaml`, showing one specific technique in isolation).

| File | Demonstrates | Used by |
| --- | --- | --- |
| `queue-and-retry-tuning.yaml` | Explicit `sending_queue`/`retry_on_failure` tuning beyond this module's defaults | `../../labs/lab-17-backpressure-and-retries.md` |
| `cardinality-limiting.yaml` | `attributes` processor dropping/hashing a high-cardinality label before it reaches Prometheus | `../../labs/lab-19-cardinality-control.md` |
| `filter-by-attribute.yaml` | `filter` processor dropping telemetry matching an OTTL condition | `../../labs/lab-18-telemetry-filtering.md` |
