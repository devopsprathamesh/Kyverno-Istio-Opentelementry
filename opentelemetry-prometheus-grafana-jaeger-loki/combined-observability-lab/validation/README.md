# Validation

Confirms every component from [`../installation/README.md`](../installation/README.md) is not just installed, but genuinely working together.

```bash
cd ..   # module root
make validate-installation   # every component, individually, plus end-to-end telemetry presence
make test-runtime             # the full per-tool + end-to-end + correlation + sampling + resilience suite
```

## What `test-runtime` covers, in this capstone's context

| Script | Confirms |
| --- | --- |
| `prometheus-test.sh`, `grafana-test.sh`, `jaeger-test.sh`, `loki-test.sh`, `collector-test.sh` | Each backend/component individually healthy |
| `traces-test.sh`, `metrics-test.sh`, `logs-test.sh` | Each signal reaches its backend through the FULL demo app + pipeline (not a direct test payload) |
| `correlation-test.sh` | A real trace_id genuinely appears in both Jaeger and Loki — the incident workflow's core dependency |
| `sampling-test.sh` | Tail sampling's error-trace guarantee holds under real application traffic |
| `resilience-test.sh` | The pipeline survives a real backend outage without data loss beyond its documented bounds |

If every script above passes, [`../scenarios/incident-workflow.md`](../scenarios/incident-workflow.md) is guaranteed to work — that scenario has no dependency `test-runtime` doesn't already, more narrowly, verify.

## Manual spot-check

```bash
make status
```
Every pod in `observability`/`opentelemetry`/`otel-demo` should show `Running`, no restarts beyond what's expected from labs you may have run (e.g. `lab-20-troubleshooting.md`'s deliberate restarts).
