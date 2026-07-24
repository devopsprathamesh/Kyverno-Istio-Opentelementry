# Demo Application

```text
Client
  → frontend            (Node.js/Express, AUTO-instrumented)
      → order-service    (Python/FastAPI, MANUALLY instrumented)
          → inventory-service  (Python/FastAPI, AUTO-instrumented)
          → payment-service    (Python/FastAPI, MANUALLY instrumented, configurable failure/latency)
```

See root `../docs/DECISIONS.md` ADR-030 (image distribution: local build + direct containerd import, no registry) and ADR-031 (two-language app, explicit auto-vs-manual instrumentation split).

## Instrumentation split (exactly as required — see each service's own file header)

| Service | Language | Instrumentation | Notable |
| --- | --- | --- | --- |
| `frontend` | Node.js | **Auto** (`operator/instrumentation/nodejs-instrumentation.yaml`) | Zero `@opentelemetry/*` SDK code; only `@opentelemetry/api` (no-op interface package) for log correlation |
| `order-service` | Python | **Manual** (`order-service/app.py`) | Custom span `order.create`, custom metrics `orders_total`/`order_processing_duration`, calls both downstream services |
| `inventory-service` | Python | **Auto** (`operator/instrumentation/python-instrumentation.yaml`) | Zero `opentelemetry-*` packages in `requirements.txt` at all |
| `payment-service` | Python | **Manual** (`payment-service/app.py`) | Custom span `payment.authorize`, custom metrics `payment_authorizations_total`/`payment_failures_total`, reads `LATENCY_MS`/`FAILURE_PERCENT` fresh per request |

## Building and deploying (no registry, ever)

```bash
cd ../                                    # module root
make build-demo-images                    # builds all 5 images locally, imports into every cluster node's containerd
make deploy-demo                          # applies kubernetes/*/deployment.yaml + service.yaml
```

`kubernetes/*/deployment.yaml` all use `imagePullPolicy: Never` — they will only ever run the exact image `build-demo-images` imported, never attempt a registry pull. See `../scripts/build-demo-images.sh` and `../docs/DECISIONS.md` ADR-030.

## Local testing without Kubernetes (optional, convenience only)

```bash
cd docker
docker compose up --build
curl -s http://localhost:3000/
```
See `docker/docker-compose.yml`'s header comment — no OTLP collector is wired up here, so traces/metrics/logs will not export (harmlessly); this is for exercising the HTTP call chain and business logic only.

## Offline unit tests

```bash
cd tests
pip install pytest
PYTHONPATH=../payment-service pytest test_payment_service_logic.py
PYTHONPATH=../inventory-service pytest test_inventory_service_logic.py
```

## Controlling failure/latency (payment-service)

```bash
cd ../                     # module root
make inject-latency         # or: ./scripts/inject-latency.sh 1500 apply
make inject-errors          # or: ./scripts/inject-errors.sh 30 apply
```
Both patch `payment-service`'s Deployment env vars via `kubectl set env` (a rolling restart), never by editing this directory's manifests directly — see `labs/lab-10-fault-injection.md` onward.
