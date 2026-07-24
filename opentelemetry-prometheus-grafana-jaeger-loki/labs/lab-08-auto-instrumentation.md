# Lab 08: Automatic Instrumentation

## Objective

Install the OpenTelemetry Operator, deploy `frontend` (Node.js) and `inventory-service` (Python) — both auto-instrumented — and directly inspect the webhook's pod mutation.

## Concepts exercised

`docs/03-opentelemetry-architecture.md`'s Operator mechanics, `operator/examples/README.md`'s expected mutation.

## Prerequisites

Lab 07 complete. Requires `make build-demo-images` (container builder + vagrant).

## Steps

1. **Install the Operator**:
   ```bash
   make install-operator
   kubectl -n opentelemetry get instrumentation
   ```

2. **Build images and deploy the demo app**:
   ```bash
   make build-demo-images
   make deploy-demo
   ```

3. **Inspect `frontend`'s mutated pod spec**:
   ```bash
   kubectl get pod -n otel-demo -l app=frontend -o jsonpath='{.spec.initContainers[*].name}{"\n"}'
   kubectl get pod -n otel-demo -l app=frontend -o jsonpath='{.spec.containers[0].env}' | python3 -m json.tool
   ```
   Expect `opentelemetry-auto-instrumentation-nodejs` and `NODE_OPTIONS` among the env vars.

4. **Inspect `inventory-service`'s mutated pod spec** (Python path):
   ```bash
   kubectl get pod -n otel-demo -l app=inventory-service -o jsonpath='{.spec.initContainers[*].name}{"\n"}'
   kubectl get pod -n otel-demo -l app=inventory-service -o jsonpath='{.spec.containers[0].env}' | python3 -m json.tool
   ```
   Expect `opentelemetry-auto-instrumentation-python` and a `PYTHONPATH` including the mounted instrumentation directory.

5. **Confirm `order-service`/`payment-service` (manually instrumented) show NEITHER of these** — no init container, no injected `OTEL_*` env vars from the webhook:
   ```bash
   kubectl get pod -n otel-demo -l app=order-service -o jsonpath='{.spec.initContainers[*].name}{"\n"}'
   ```
   Expect empty output.

6. **Generate a request and confirm auto-instrumented traces actually appear**:
   ```bash
   kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/
   make port-forward-jaeger &
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=frontend' | python3 -m json.tool
   ```

## Validation

Steps 3–5's commands show exactly the differentiated behavior described — auto-instrumented services mutated, manually-instrumented ones not.

## Failure scenarios to notice

Remove the `instrumentation.opentelemetry.io/inject-nodejs` annotation from a local copy of `demo-application/kubernetes/frontend/deployment.yaml`, apply it, and repeat step 3 — confirm the init container disappears and `frontend`'s traces stop appearing in Jaeger, direct proof the annotation (not something else) is what triggers injection. Restore the annotation afterward.

## Cleanup

Leave the Operator and demo app installed for later labs.

## Reflection

`operator/examples/README.md` describes the EXPECTED mutation based on documented Operator behavior. Now that you've run steps 3–4 yourself, did the actual mutation match exactly, or did you find any difference worth noting for future reference?
