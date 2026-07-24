# Lab 16: Collector Scaling

## Objective

Scale the Gateway Deployment under increasing load and observe resource usage, queue depth, and export success rate at each step.

## Concepts exercised

`docs/10-collector-deployment-patterns.md`'s Gateway scaling axis, `docs/18-performance-and-capacity.md`.

## Prerequisites

Lab 07 complete, demo app deployed.

## Steps

1. **Baseline at 1 Gateway replica**:
   ```bash
   kubectl -n opentelemetry scale deployment/otel-collector-gateway --replicas=1
   kubectl -n opentelemetry rollout status deployment/otel-collector-gateway
   ```

2. **Drive substantial concurrent load**:
   ```bash
   make generate-load ARGS="500 50 60"
   ```

3. **Observe resource usage and internal metrics during the load**:
   ```bash
   kubectl -n opentelemetry top pod -l app=otel-collector-gateway
   kubectl -n opentelemetry port-forward svc/otel-collector-gateway 8888:8888 &
   curl -s http://localhost:8888/metrics | grep -E 'otelcol_receiver_refused|otelcol_exporter_queue_size'
   ```
   Note whether any `otelcol_receiver_refused_*` activity appears (memory_limiter under pressure) at this replica count.

4. **Scale to 3 replicas and repeat the same load**:
   ```bash
   kubectl -n opentelemetry scale deployment/otel-collector-gateway --replicas=3
   kubectl -n opentelemetry rollout status deployment/otel-collector-gateway
   make generate-load ARGS="500 50 60"
   kubectl -n opentelemetry top pod -l app=otel-collector-gateway
   ```
   Compare per-pod resource usage and refused-telemetry counts against step 3.

5. **Check the tail-sampling caveat directly** — with 3 replicas and no consistent routing, confirm (via `docs/10-collector-deployment-patterns.md`'s explanation) that spans of one trace CAN land on different replicas, and reason about what that means for tail sampling's correctness at this replica count (this lab doesn't implement consistent routing, so this is a reasoning exercise, not something you can directly observe going wrong at this small scale/short trace lifetime).

## Validation

You can state, with actual numbers from steps 3 and 4, whether horizontal scaling measurably reduced refused-telemetry activity under the same load.

## Failure scenarios to notice

Deliberately under-provision by scaling to 1 replica with `resources.limits.memory` reduced (edit a copy of `collector/gateway/deployment.yaml`, reapply) and repeat step 2's load — observe `otelcol_receiver_refused_*` climb and, if severe enough, an OOMKill — a controlled, safe demonstration of `docs/21-troubleshooting.md`'s "Collector OOMKilled" scenario. Revert afterward.

## Cleanup

```bash
kubectl -n opentelemetry scale deployment/otel-collector-gateway --replicas=1
```
(Or `--replicas=2` to match the `recommended` profile's default if you're continuing with that profile.)

## Reflection

Step 5 asked you to reason about correctness, not observe a failure directly. Design (on paper) a test that WOULD directly demonstrate tail-sampling inconsistency across replicas — what load pattern and trace shape would make the problem actually visible?
