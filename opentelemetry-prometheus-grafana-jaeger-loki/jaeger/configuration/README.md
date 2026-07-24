# Jaeger Configuration

The actual, applied configuration is [`../../install/jaeger/values-minimum.yaml`](../../install/jaeger/values-minimum.yaml) / [`values-recommended.yaml`](../../install/jaeger/values-recommended.yaml) — Helm values for the `jaegertracing/helm-charts` chart (not the deprecated Jaeger Operator — see `docs/DECISIONS.md` ADR-027).

## Storage backend by profile

| Profile | `SPAN_STORAGE_TYPE` | Persistence |
| --- | --- | --- |
| `minimum` | `memory` | None — traces lost on pod restart, explicitly non-production (`docs/13-jaeger-architecture.md`) |
| `recommended` | `badger` (embedded, persistent) | PVC, `config/retention.env` `JAEGER_PVC_SIZE_RECOMMENDED` |

Neither profile is real production Jaeger — a production deployment needs Elasticsearch or Cassandra as the storage backend plus separately-scaled collector/query components, documented but not implemented here (`docs/16-production-design.md`).

## OTLP ingestion

Jaeger v2 has a native, stable OTLP receiver (no separate Collector needed in front of it) — gRPC on `config/versions.env`'s `JAEGER_OTLP_GRPC_PORT` (4317), HTTP on `JAEGER_OTLP_HTTP_PORT` (4318). Enabled via `allInOne.args: [--collector.otlp.enabled=true]` in both values files.
