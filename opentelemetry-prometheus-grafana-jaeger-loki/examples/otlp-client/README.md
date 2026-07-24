# Minimal OTLP Client (No SDK)

`send-raw-otlp.py` is a deliberately unwrapped, standalone version of what `scripts/lib/observability.sh`'s `send_test_otlp_trace`/`send_test_otlp_log` do internally — read this file if you want to see the raw OTLP/HTTP JSON wire format directly, with no SDK, no bash wrapper, no library abstraction in the way.

## Usage

```bash
kubectl -n opentelemetry port-forward svc/otel-collector-gateway 14318:4318 &
python3 send-raw-otlp.py trace --endpoint http://localhost:14318 --service my-test-service
python3 send-raw-otlp.py log   --endpoint http://localhost:14318 --service my-test-service --message "hello"
```

## Why this exists separately from `scripts/lib/observability.sh`

That file's helpers are optimized for reuse inside other scripts (bash functions, minimal output). This file is optimized for *reading* — it's the thing to open when you want to understand exactly what bytes go over the wire for an OTLP/HTTP trace or log payload, matching `docs/02-opentelemetry-fundamentals.md`'s OTLP HTTP diagram directly.
