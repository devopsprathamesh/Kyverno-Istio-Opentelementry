# Lab 09: Manual Instrumentation

## Objective

Read and trace through `order-service`/`payment-service`'s explicit SDK setup, then add one new custom span/attribute yourself and confirm it appears in Jaeger.

## Concepts exercised

`docs/02-opentelemetry-fundamentals.md`'s manual-instrumentation path, custom spans/events/attributes/metrics.

## Prerequisites

Lab 08 complete.

## Steps

1. **Read `demo-application/order-service/app.py`'s `setup_telemetry()`** — identify: the `TracerProvider`, the `Resource`, the `BatchSpanProcessor`, the `OTLPSpanExporter`. Confirm none of this exists in `inventory-service/app.py` (lab 08's contrast).

2. **Trace the custom span tree** in `create_order()` — `order.create` (custom) → `inventory.check` (custom, wrapping an auto-instrumented `httpx` CLIENT span) → `payment.authorize` (custom).

3. **Generate a request and confirm the custom spans appear**, distinct from the framework-auto-generated ones:
   ```bash
   kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/
   make port-forward-jaeger &
   ```
   In the Jaeger UI, open the resulting trace — you should see `order.create`/`inventory.check`/`payment.authorize` as named, custom spans (not generic `POST /orders`-style auto-generated names).

4. **Add a new custom attribute** — edit your own copy of `demo-application/order-service/app.py`, add one line inside the `order.create` span block:
   ```python
   span.set_attribute("lab09.custom_marker", "hello-from-lab-09")
   ```
   Rebuild and redeploy just this service:
   ```bash
   docker build -t otel-demo/order-service:1.0.0 -f demo-application/order-service/Dockerfile demo-application/order-service
   # re-import into node containerd per scripts/build-demo-images.sh's pattern, or re-run the full build-demo-images.sh
   kubectl -n otel-demo rollout restart deployment/order-service
   ```

5. **Confirm the new attribute appears** on the next trace's `order.create` span in Jaeger.

## Validation

The custom span tree from step 2/3 matches `docs/04-distributed-tracing.md`'s described tree exactly, and your added attribute from step 4 is visible in step 5.

## Failure scenarios to notice

Add a custom metric instrument (`meter.create_counter(...)`) but forget to actually call `.add()` anywhere in a request path — confirm it never appears in Prometheus (`curl .../api/v1/query?query=<your_metric_name>` returns empty) even though the instrument was created. This demonstrates that *creating* an instrument and *recording* a value with it are two separate steps — only the second one produces queryable data.

## Cleanup

Revert your local edit to `order-service/app.py` if you don't want it to persist (not committed anywhere by this lab automatically).

## Reflection

`payment-service` and `order-service` both use manual instrumentation, but only `payment-service` has environment-variable-driven runtime behavior (`LATENCY_MS`/`FAILURE_PERCENT`). Is that difference a consequence of manual vs. auto instrumentation, or an unrelated design choice? Justify your answer from what you've read in both files.
