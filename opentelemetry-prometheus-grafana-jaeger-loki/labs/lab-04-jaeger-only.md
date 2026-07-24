# Lab 04: Jaeger Only

## Objective

Install Jaeger and send it a test trace directly via OTLP — no Collector, no demo app.

## Concepts exercised

Jaeger v2's native OTLP receiver, all-in-one mode's real limitations (`docs/13-jaeger-architecture.md`).

## Prerequisites

Lab 00 complete.

## Steps

1. **Install Jaeger**:
   ```bash
   make install-jaeger LAB_PROFILE=minimum
   make validate-jaeger
   ```

2. **Send a test trace directly** (bypassing the Collector entirely):
   ```bash
   source scripts/lib/common.sh
   source scripts/lib/observability.sh
   kubectl -n observability port-forward svc/jaeger-collector 14318:4318 &
   kubectl -n observability port-forward svc/jaeger-query 16686:16686 &
   TRACE_ID=$(send_test_otlp_trace 14318 lab04-manual-test)
   echo "Sent: ${TRACE_ID}"
   ```

3. **Find it in the UI**: open `http://localhost:16686`, select service `lab04-manual-test`, click Find Traces.

4. **Find it via the API**:
   ```bash
   curl -s "http://localhost:16686/api/traces/${TRACE_ID}" | python3 -m json.tool
   ```

5. **Restart the pod and confirm the trace is gone** (minimum profile only — in-memory storage):
   ```bash
   kubectl -n observability delete pod -l app.kubernetes.io/instance=jaeger
   kubectl -n observability wait --for=condition=Ready pod -l app.kubernetes.io/instance=jaeger --timeout=60s
   curl -s "http://localhost:16686/api/traces/${TRACE_ID}"
   ```
   Expect an empty/not-found result — directly, hands-on confirming `install/jaeger/values-minimum.yaml`'s in-memory-storage warning is real, not theoretical.

## Validation

```bash
bash tests/jaeger-test.sh
```

## Failure scenarios to notice

Try step 5 again after switching to the `recommended` profile (`make install-jaeger LAB_PROFILE=recommended`) and repeat the send-trace-then-restart sequence — the trace should now survive the restart (badger persistent storage + PVC). Compare both outcomes directly.

## Cleanup

```bash
# Ctrl-C both port-forwards
```
Leave Jaeger installed for later labs.

## Reflection

`jaeger/queries/jaeger-api-examples.md`'s `/api/dependencies` endpoint returns an empty graph right now — why, specifically, given that you just sent a real trace?
