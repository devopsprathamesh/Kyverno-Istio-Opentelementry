# Lab 07: Agent and Gateway Collectors

## Objective

Install this module's real Collector topology — Agent DaemonSet + Gateway Deployment — and inspect both independently before any application traffic flows through them.

## Concepts exercised

`docs/10-collector-deployment-patterns.md`'s agent-and-gateway architecture, in its actual installed form.

## Prerequisites

Labs 02, 04, 05 complete (backends installed).

## Steps

1. **Install**:
   ```bash
   make install-collector LAB_PROFILE=minimum
   make validate-collector
   ```

2. **Confirm one Agent pod per node**:
   ```bash
   kubectl -n opentelemetry get pods -l app=otel-collector-agent -o wide
   kubectl get nodes
   ```
   Counts should match.

3. **Inspect the Gateway's health and internal metrics**:
   ```bash
   kubectl -n opentelemetry port-forward svc/otel-collector-gateway 13133:13133 8888:8888 &
   curl -s http://localhost:13133/
   curl -s http://localhost:8888/metrics | grep otelcol_process
   ```

4. **Send a trace directly to the Gateway** and confirm it reaches Jaeger (this lab's demo app's actual default path, per `operator/instrumentation/*.yaml`'s comment):
   ```bash
   kubectl -n opentelemetry port-forward svc/otel-collector-gateway 14318:4318 &
   source scripts/lib/common.sh
   source scripts/lib/observability.sh
   send_test_otlp_trace 14318 lab07-gateway-test
   ```

5. **Confirm the Agent is actively tailing logs**, even with no application deployed yet — it reads its own and every other pod's logs already running in the cluster:
   ```bash
   kubectl -n opentelemetry logs -l app=otel-collector-agent --tail=5
   ```

## Validation

```bash
bash tests/collector-test.sh
```

## Failure scenarios to notice

Scale the Gateway to 0 (`kubectl -n opentelemetry scale deployment/otel-collector-gateway --replicas=0`), then check the Agent's own logs — it should show connection-refused/retry activity trying to reach the Gateway (`sending_queue`/`retry_on_failure` absorbing it), NOT the Agent itself crashing. Scale back to 1 and confirm it recovers without intervention. This is a preview of `labs/lab-17-backpressure-and-retries.md`'s deeper exercise.

## Cleanup

Leave installed for later labs, or:
```bash
make clean-collector
```

## Reflection

Step 4 sent a trace directly to the Gateway, bypassing the Agent entirely — and it worked. Given that, what specifically is the Agent's OTLP receiver actually for in this lab's default configuration, if the demo app doesn't use it?
