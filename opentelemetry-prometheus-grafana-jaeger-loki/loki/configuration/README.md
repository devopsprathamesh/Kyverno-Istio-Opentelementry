# Loki Configuration

The actual, applied configuration is [`../../install/loki/values-minimum.yaml`](../../install/loki/values-minimum.yaml) / [`values-recommended.yaml`](../../install/loki/values-recommended.yaml) — `deploymentMode: Monolithic` (current chart terminology — see `docs/VERSIONS.md` Phase 5 addendum), filesystem storage, single-tenant (`auth_enabled: false`).

## Why not Promtail

Promtail is mentioned here only as historical/comparative context, per this phase's explicit instructions — it is never used as this module's log-collection mechanism. Default collection is exclusively the OpenTelemetry Collector's `filelog` receiver (`../../collector/agent/configmap.yaml`), which reads the same node-local `/var/log/pods/*/*/*.log` files Promtail would have, but integrates with the rest of this module's unified OTLP pipeline (trace-context injection, `k8sattributes` enrichment, tail-sampling-adjacent processing) instead of being a separate, log-only agent. See root `docs/DECISIONS.md` ADR-007.

## Why not the `loki` exporter

The OpenTelemetry Collector Contrib `loki` exporter component was **removed** (not merely deprecated) around contrib v0.130.0 — this module's pinned `0.157.0` does not have it. The Collector Gateway uses the standard `otlphttp` exporter pointed at Loki's native OTLP ingestion endpoint instead — see `../../collector/gateway/configmap.yaml`'s `otlphttp/loki` exporter and `docs/06-logs.md`.
