# Sending a Test OTLP Trace Directly to Jaeger

Bypasses the Collector entirely — useful for isolating "is Jaeger itself broken" from "is the Collector pipeline broken" (see `docs/21-troubleshooting.md`'s triage ordering).

```bash
kubectl -n observability port-forward svc/jaeger-collector 14318:4318 &
kubectl -n observability port-forward svc/jaeger-query 16686:16686 &

source scripts/lib/common.sh
source scripts/lib/observability.sh
TRACE_ID=$(send_test_otlp_trace 14318 manual-test-service)
echo "Sent trace: ${TRACE_ID}"

sleep 3
curl -s "http://127.0.0.1:16686/api/traces/${TRACE_ID}" | python3 -m json.tool
```

Or directly reachable via the Jaeger UI at `http://127.0.0.1:16686` — search for service `manual-test-service`.

This is exactly what `tests/jaeger-test.sh` and `labs/lab-04-jaeger-only.md` do, scripted.
