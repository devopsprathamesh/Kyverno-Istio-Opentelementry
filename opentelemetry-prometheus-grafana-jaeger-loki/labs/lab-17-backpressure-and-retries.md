# Lab 17: Backpressure and Retries

## Objective

Take Jaeger down entirely, prove the Collector Gateway keeps functioning (queuing and retrying rather than crashing), watch the queue metrics rise, then bring Jaeger back and confirm queued data actually gets delivered.

## Concepts exercised

`docs/09-collector-internals.md`'s retry/queue flow, backpressure, data-loss boundaries.

## Prerequisites

Lab 07 complete, demo app deployed.

## Steps

1. **Baseline: confirm traces are flowing normally**:
   ```bash
   kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/
   ```

2. **Take Jaeger down**:
   ```bash
   kubectl -n observability scale deployment/jaeger --replicas=0
   ```

3. **Generate traffic while Jaeger is down**:
   ```bash
   make generate-load ARGS="100 10 30"
   ```

4. **Confirm the Gateway is still healthy** (not crashing):
   ```bash
   kubectl -n opentelemetry get pods -l app=otel-collector-gateway
   ```

5. **Watch the failed-export and queue metrics rise**:
   ```bash
   kubectl -n opentelemetry port-forward svc/otel-collector-gateway 8888:8888 &
   curl -s http://localhost:8888/metrics | grep -E 'otelcol_exporter_send_failed_spans|otelcol_exporter_queue_size'
   ```

6. **Bring Jaeger back and confirm recovery**:
   ```bash
   kubectl -n observability scale deployment/jaeger --replicas=1
   kubectl -n observability rollout status deployment/jaeger
   ```
   Wait a minute, then check whether any of the "in flight during the outage" traces eventually made it through (retry succeeded before `max_elapsed_time`) or were permanently dropped (outage outlasted the retry budget):
   ```bash
   make port-forward-jaeger &
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=frontend' --data-urlencode 'limit=200' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'
   ```

## Validation

```bash
bash tests/resilience-test.sh
```

## Failure scenarios to notice

Extend the outage duration (keep Jaeger scaled to 0 for longer than `retry_on_failure.max_elapsed_time`, which is 300s in `collector/gateway/configmap.yaml`) and confirm data sent early in the outage is genuinely, permanently lost (not retried forever) — this lab's queue has bounds, and understanding exactly where those bounds are is the point of this exercise, not treating "resilience" as unlimited.

## Cleanup

```bash
kubectl -n observability scale deployment/jaeger --replicas=1
```

## Reflection

`docs/16-production-design.md` names "no persistent export queue" as a real, current gap in this lab. Given what you just observed, explain precisely what a *persistent* (not just in-memory) queue would have additionally protected against, that this lab's current in-memory `sending_queue` does not.
