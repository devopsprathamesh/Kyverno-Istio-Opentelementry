# Installation Sequence

The exact, complete sequence for this capstone — identical to the module's own Quick Start (root `README.md`), reproduced here with the reasoning for each step's ordering.

```bash
cd ..   # module root

make prerequisites          # tools present?
make verify-cluster         # right cluster, healthy Cilium/kube-proxy/CoreDNS/storage?

make install-all LAB_PROFILE=recommended
# internally, in this exact order (scripts/install-all.sh):
#   1. install-operator    — CRDs + webhook must exist before any Instrumentation-annotated pod is created
#   2. install-prometheus  — kube-prometheus-stack, including the ServiceMonitor/PodMonitor CRDs
#   3. install-jaeger      — backend must exist before the Gateway tries to export to it
#   4. install-loki        — same reasoning
#   5. install-collector   — Gateway before Agent (Agent's exporter needs the Gateway Service to exist)
#   6. install-grafana     — last, so its datasource health checks have real backends to check against

make validate-installation  # confirms every component from step above, plus end-to-end telemetry

make build-demo-images      # local build + containerd import, no registry (docs/DECISIONS.md ADR-030)
make deploy-demo            # applies demo-application/kubernetes/*

make generate-load          # produces real traffic for every dashboard/query in scenarios/ to have data
make validate                # full end-to-end validation, including trace/metric/log presence
```

## What to check after each phase

After `install-all`: `make status` — every pod in `observability`/`opentelemetry` should be `Running`.
After `deploy-demo`: `kubectl -n otel-demo get pods` — 4 services + no load-generator pod yet (it runs as a one-shot Job via `generate-load`, not a standing Deployment).
After `generate-load`: `make port-forward-jaeger` and confirm at least one trace exists for each of the 4 services.
