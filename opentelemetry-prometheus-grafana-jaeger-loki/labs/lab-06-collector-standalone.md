# Lab 06: Collector Standalone

## Objective

Deploy one Collector instance, minimal pipeline, and watch its `debug` exporter show exactly what it receives — the fastest way to build real intuition for receiver→processor→exporter before adding the agent/gateway split's complexity.

## Concepts exercised

`docs/09-collector-internals.md`'s pipeline model, `docs/10-collector-deployment-patterns.md`'s standalone pattern.

## Prerequisites

Labs 02, 04, 05 complete (Prometheus/Jaeger/Loki installed — the standalone Collector's exporters target them).

## Steps

1. **Deploy the standalone Collector**:
   ```bash
   kubectl apply -f install/namespaces/
   kubectl apply -f collector/standalone/configmap.yaml
   kubectl apply -f collector/standalone/deployment.yaml
   kubectl apply -f collector/standalone/service.yaml
   kubectl -n opentelemetry rollout status deployment/otel-collector-standalone
   ```

2. **Watch its stdout live** (the `debug` exporter is wired into every pipeline — `collector/standalone/configmap.yaml`):
   ```bash
   kubectl -n opentelemetry logs -f deployment/otel-collector-standalone &
   ```

3. **Send it a test trace and a test log**:
   ```bash
   kubectl -n opentelemetry port-forward svc/otel-collector-standalone 14318:4318 &
   source scripts/lib/common.sh
   source scripts/lib/observability.sh
   send_test_otlp_trace 14318 lab06-standalone-test
   send_test_otlp_log 14318 lab06-standalone-test "hello from the standalone collector"
   ```

4. **Read the `debug` exporter's `verbosity: detailed` output** in the log stream from step 2 — you should see the full span/log record printed, attribute by attribute, exactly as the Collector's internal data model represents it.

5. **Confirm it also reached the real backends** (the standalone config exports to both `debug` AND the real backends simultaneously):
   ```bash
   make port-forward-jaeger &
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=lab06-standalone-test' | python3 -m json.tool
   ```

## Validation

The `debug` exporter's stdout output and the real backend's stored data both show the same telemetry — direct proof the pipeline actually processed and forwarded what it received, not just logged it.

## Failure scenarios to notice

Edit a local copy of `collector/standalone/configmap.yaml` to remove the `batch` processor from the traces pipeline, reapply, and send another test trace — observe it's exported essentially immediately (no batching delay) rather than waiting for `timeout: 5s`, directly showing what the `batch` processor's job actually is.

## Cleanup

```bash
kubectl delete -f collector/standalone/deployment.yaml -f collector/standalone/service.yaml -f collector/standalone/configmap.yaml
```
This lab-only Collector is never part of `make install-all`/`make clean` — remove it manually as shown above.

## Reflection

The `debug` exporter is never used in `collector/agent/configmap.yaml` or `collector/gateway/configmap.yaml` (this module's real install). Why not — what would go wrong if you left `verbosity: detailed` debug logging enabled in a production-bound Collector pipeline processing real traffic volume?
