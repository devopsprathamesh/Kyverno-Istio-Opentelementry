# Lab 01: Observability Without OpenTelemetry

## Objective

Deploy the demo application without any instrumentation active, and directly experience why `kubectl logs` alone makes troubleshooting a multi-service failure difficult — before this module gives you the tools that fix it.

## Concepts exercised

Monitoring vs. observability (`docs/01-observability-fundamentals.md`), what Kubernetes gives you for free (`docs/15-kubernetes-observability.md`).

## Prerequisites

Lab 00 complete. Requires `make build-demo-images` (a container builder + vagrant) since this lab deploys the real demo app.

## Steps

1. **Build and deploy the demo app** (no observability stack installed yet):
   ```bash
   make build-demo-images
   make deploy-demo
   ```

2. **Force a failure** (payment declines) without any tracing/metrics/correlation available yet:
   ```bash
   make inject-errors ARGS="80 apply"
   kubectl -n otel-demo run l01-client --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 60
   kubectl -n otel-demo wait --for=condition=Ready pod/l01-client --timeout=60s
   for i in $(seq 1 5); do kubectl -n otel-demo exec l01-client -- curl -s -X POST http://frontend.otel-demo.svc.cluster.local:3000/; echo; done
   ```

3. **Try to diagnose using only `kubectl logs`** — pick one failed request and try to find out *why* it failed, using only:
   ```bash
   kubectl -n otel-demo logs -l app=frontend --tail=20
   kubectl -n otel-demo logs -l app=order-service --tail=20
   kubectl -n otel-demo logs -l app=payment-service --tail=20
   ```
   Notice: correlating a specific failed request across three separate log streams, with no shared request ID (yet — before instrumentation), requires eyeballing timestamps and hoping nothing else happened concurrently.

## Validation

You can articulate, concretely, which specific question `kubectl logs` alone could not answer confidently (e.g., "which exact order ID failed, and can I prove it was THIS request, not a coincidentally-nearby one").

## Failure scenarios to notice

Run several requests concurrently (`for i in $(seq 1 20); do ... & done; wait`) and try the same log-correlation exercise — it gets dramatically harder with concurrent requests, which is the realistic case, not the artificially serial one.

## Cleanup

```bash
make inject-errors ARGS="0 revert"
kubectl -n otel-demo delete pod l01-client
```

## Reflection

This lab's app is already instrumented in its source code (auto/manual, per `docs/DECISIONS.md` ADR-031) — you just haven't installed the Collector/Prometheus/Jaeger/Loki/Grafana stack yet, so the telemetry has nowhere to go. What does that tell you about the relationship between "instrumenting an application" and "having observability" — are they the same thing?
