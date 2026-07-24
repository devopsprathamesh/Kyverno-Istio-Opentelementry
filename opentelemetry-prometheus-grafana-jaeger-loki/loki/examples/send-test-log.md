# Sending a Test OTLP Log Directly to Loki

Bypasses the Collector entirely — isolates "is Loki itself broken" from "is the Collector pipeline broken."

```bash
kubectl -n observability port-forward svc/loki 13100:3100 &

source scripts/lib/common.sh
source scripts/lib/observability.sh
send_test_otlp_log 13100 manual-test-service "this is a manual test log line"

sleep 2
curl -s -G http://127.0.0.1:13100/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="manual-test-service"}' | python3 -m json.tool
```

This is exactly what `tests/loki-test.sh` and `labs/lab-05-loki-only.md` do, scripted. Note the endpoint used by `send_test_otlp_log` is Loki's OTLP path (`/v1/logs`, appended by convention in that helper) — not the legacy Loki push API (`/loki/api/v1/push`), which this module never uses.
