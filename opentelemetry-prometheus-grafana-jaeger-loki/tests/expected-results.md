# Expected Test Results

What a healthy run of each script in this directory looks like. See [`../../docs/VALIDATION-STATUS.md`](../../docs/VALIDATION-STATUS.md) (root) for what has actually been run in this repository so far — as of Phase 5: static checks only, see that document.

## `static-validation.sh` (`make test-static`, cluster-free)

```text
==> 1. bash -n and ShellCheck              [PASS] x N scripts
==> 2. YAML structural validation           [PASS] All N YAML files parse.
==> 3. JSON structural validation           [PASS] All N JSON files parse (dashboards, package.json).
==> 4. Collector configuration sanity       [PASS] No deprecated components or malformed Loki OTLP endpoints.
==> 5. Demo application source syntax       [PASS] Python compiles / Node.js '--check' passes.
==> 6. Dockerfile review                    [PASS] Pinned base image, non-root USER, no ':latest'.
==> 7. Manifest quality checks              [PASS] No ':latest' image tags.
==> 8. Helm lint                             [SKIP] network-dependent, not attempted offline.
==> 9. Markdown link check                  [PASS] All relative markdown links resolve.
==> 10. Makefile help                       [PASS] make help succeeded, listing N targets.
```

A `[SKIP]` for step 8 is expected and non-fatal without network access — the reason is always printed. Steps 5's Node.js check is skipped (not failed) if `node` isn't installed on the validating host.

## `validate-installation.sh [scope]` (requires a live cluster)

```text
[PASS] CRD opentelemetrycollectors.opentelemetry.io exists
[PASS] Operator Deployment Ready
[PASS] Prometheus query API works ('up' returns results)
[PASS] Grafana health endpoint OK
[PASS] Grafana datasource 'prometheus'/'jaeger'/'loki' healthy
[PASS] Jaeger Query UI reachable
[PASS] Test trace searchable in Jaeger
[PASS] Loki readiness endpoint OK
[PASS] Collector Agent DaemonSet Ready on all nodes
[PASS] Collector Gateway Deployment Ready
```

Before `make install-all` has run: exits 0 immediately with `[INFO] No reachable cluster`.

## `prometheus-test.sh` / `grafana-test.sh` / `jaeger-test.sh` / `loki-test.sh` / `collector-test.sh`

Each isolates its own tool — `jaeger-test.sh`/`loki-test.sh` send a test OTLP payload **directly** to the backend, bypassing the Collector entirely, so a failure here specifically means "this backend itself is broken," not "the pipeline in front of it is broken." See `docs/21-troubleshooting.md`'s triage ordering for why this distinction matters.

```text
[PASS] Query API works ('up' returns results)
[PASS] Datasource 'prometheus' healthy
[PASS] Test OTLP trace accepted (trace_id=4bf92f...)
[PASS] Test trace is searchable in Jaeger
[PASS] Test OTLP log is searchable in Loki
[PASS] Agent DaemonSet Ready on all nodes
```

## `traces-test.sh` / `metrics-test.sh` / `logs-test.sh`

End-to-end, through the real demo app and the full Agent→Gateway→backend pipeline. Skipped (not failed) if `make deploy-demo` hasn't run.

```text
[PASS] Traces found for frontend
[PASS] Traces found for order-service
[PASS] Traces found for inventory-service
[PASS] Traces found for payment-service
[PASS] Demo app business metric 'orders_total' visible in Prometheus
[PASS] Demo app logs are reaching Loki
[PASS] Kubernetes namespace/service metadata present on log streams
```

## `correlation-test.sh`

```text
[PASS] Obtained real trace_id from Jaeger: 4bf92f3577b34da6a3ce929d0e0e4736
[PASS] The SAME trace_id is present in a Loki log record — trace-log correlation confirmed end to end
```

This is the strongest test in the suite — it doesn't just check that Grafana's correlation config exists, it proves the underlying trace_id genuinely appears identically in both backends.

## `sampling-test.sh`

```text
[INFO] Sent 10 guaranteed-error requests; found 10 error-tagged traces for payment-service in Jaeger.
[PASS] At least one error trace survived tail sampling (the 'keep-all-errors' policy)
```

A `[WARN]` (found fewer error traces than sent) is possible and non-fatal — span-status tagging conventions can vary slightly by SDK/instrumentation-library version; the hard failure condition is finding **zero**.

## `resilience-test.sh`

```text
[PASS] Collector Agent/Gateway remain healthy with the trace backend down
[PASS] Gateway's own metrics show failed-export activity while the backend is down
```

Jaeger is scaled to 0 and back to its original replica count by this script itself — always restored via a `trap`, even on failure.

## Interpreting results

- Any `[FAIL]` line means the calling script (and `make test-runtime`/`make test-static`) exits non-zero. Check [`../docs/21-troubleshooting.md`](../docs/21-troubleshooting.md).
- `[WARN]` never fails a run by itself.
- `[INFO]` lines explaining "no cluster" or "no demo namespace" are the honest, correct response, not a silently-skipped check.
