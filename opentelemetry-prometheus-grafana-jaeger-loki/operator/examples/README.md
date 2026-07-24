# Operator Injection Examples

## How to inspect the actual mutation (do this instead of trusting this README)

```bash
kubectl get pod -n otel-demo -l app=frontend -o yaml > /tmp/frontend-pod.yaml
kubectl get pod -n otel-demo -l app=frontend -o yaml | grep -A3 initContainers
kubectl get pod -n otel-demo -l app=frontend -o jsonpath='{.items[0].spec.containers[0].env}' | python3 -m json.tool
```
This is the ground truth — `labs/lab-08-auto-instrumentation.md` walks through it step by step. What follows is what the Operator is *expected* to produce, based on its documented injection behavior for the Node.js/Python auto-instrumentation paths — described here for orientation before you run the lab, not as a substitute for actually looking.

## Expected mutation, Node.js (frontend)

The webhook, triggered by the pod's `instrumentation.opentelemetry.io/inject-nodejs: "opentelemetry/nodejs-instrumentation"` annotation (see `../instrumentation/nodejs-instrumentation.yaml`), is expected to:

1. Add an **init container** (`opentelemetry-auto-instrumentation-nodejs`) that copies the Node.js auto-instrumentation agent files into a shared `emptyDir` volume.
2. Mount that `emptyDir` into the application container at a fixed path (typically `/otel-auto-instrumentation-nodejs`).
3. Inject environment variables into the application container: `NODE_OPTIONS=--require /otel-auto-instrumentation-nodejs/autoinstrumentation.js`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES` (with `k8s.pod.name`/`k8s.namespace.name`/etc. populated via the Downward API), `OTEL_PROPAGATORS`, `OTEL_TRACES_SAMPLER`.
4. The application's own source code is never modified — the `NODE_OPTIONS` require-hook is what actually wires up instrumentation at process start.

## Expected mutation, Python (inventory-service)

Same webhook mechanism, triggered by `instrumentation.opentelemetry.io/inject-python: "opentelemetry/python-instrumentation"` (see `../instrumentation/python-instrumentation.yaml`):

1. An init container copies the `opentelemetry-python` auto-instrumentation packages into a shared `emptyDir`.
2. `PYTHONPATH` is prepended to include that mounted directory.
3. The application's actual entrypoint is wrapped with `opentelemetry-instrument` (the Operator rewrites the container's command/args, or injects it via the `PYTHONPATH`-loaded sitecustomize hook, depending on Operator version) rather than requiring the Dockerfile's `CMD` to change.
4. Same `OTEL_*` environment variables as above.

## Why order-service and payment-service look different

Neither carries an `instrumentation.opentelemetry.io/inject-python` annotation (see `../../demo-application/kubernetes/order-service/deployment.yaml` and `.../payment-service/deployment.yaml`) — no init container, no injected `OTEL_*` env vars from the webhook. They call the `opentelemetry-sdk` directly in their own source code instead (`../../demo-application/order-service/app.py`, `.../payment-service/app.py`) — see `docs/DECISIONS.md` ADR-031 and `labs/lab-09-manual-instrumentation.md`.
