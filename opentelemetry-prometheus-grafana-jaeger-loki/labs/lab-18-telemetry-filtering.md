# Lab 18: Filtering and Redaction

## Objective

Confirm sensitive fields are actually stripped before export, and confirm health-check-probe noise is actually filtered out of logs — both directly, not just by reading the config.

## Concepts exercised

`docs/17-security-and-governance.md`'s redaction, `docs/09-collector-internals.md`'s `filter` processor.

## Prerequisites

Lab 07 complete, demo app deployed.

## Steps

1. **Send a trace carrying a sensitive attribute directly**, bypassing the application (to control exactly what's sent):
   ```bash
   kubectl -n opentelemetry port-forward svc/otel-collector-gateway 14318:4318 &
   python3 - <<'PYEOF'
import json, urllib.request, secrets

trace_id = secrets.token_hex(16)
span_id = secrets.token_hex(8)
payload = {
    "resourceSpans": [{
        "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "lab18-redaction-test"}}]},
        "scopeSpans": [{"spans": [{
            "traceId": trace_id, "spanId": span_id, "name": "test-span", "kind": 1,
            "startTimeUnixNano": "1700000000000000000", "endTimeUnixNano": "1700000001000000000",
            "attributes": [
                {"key": "password", "value": {"stringValue": "should-never-appear"}},
                {"key": "customer.ssn", "value": {"stringValue": "should-never-appear"}},
                {"key": "order.id", "value": {"stringValue": "order-safe-to-keep"}},
            ],
        }]}],
    }]
}
req = urllib.request.Request("http://127.0.0.1:14318/v1/traces", data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}, method="POST")
urllib.request.urlopen(req, timeout=5)
print(trace_id)
PYEOF
   ```

2. **Confirm the sensitive attributes never reached Jaeger**:
   ```bash
   sleep 3
   make port-forward-jaeger &
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=lab18-redaction-test' --data-urlencode 'limit=1' | python3 -m json.tool
   ```
   Confirm `password`/`customer.ssn` are absent from the span's attributes, while `order.id` IS present — proving the redaction is selective (specific keys deleted), not wholesale.

3. **Confirm health-check log filtering** — check that `/health`/`/ready` probe requests never appear as log entries:
   ```bash
   make port-forward-loki &
   curl -s -G http://localhost:3100/loki/api/v1/query_range --data-urlencode '{k8s_namespace_name="otel-demo"} |= "healthz"' | python3 -m json.tool
   ```
   (This lab's demo app's actual health endpoints are `/health`/`/ready`, not `/healthz` — adjust the query to match; the point is confirming whichever health-check path your probes hit doesn't show up as log noise, per `collector/agent/configmap.yaml`'s `filter/logs` processor.)

## Validation

Step 2's trace shows selective redaction working correctly on real, sent data.

## Failure scenarios to notice

Add a new sensitive field name to your test payload that ISN'T in `collector/gateway/configmap.yaml`'s `attributes/redact.actions` list (e.g., `api_key`) and confirm it DOES pass through unredacted — a direct demonstration that this lab's redaction is an explicit allowlist-of-things-to-remove, not a pattern-based scrubber, meaning any new sensitive field name must be added explicitly (`17-security-and-governance.md`'s implicit assumption, made concrete here).

## Cleanup

None — the test span/trace has no PVC-backed persistence concern (Jaeger `minimum` profile) or expires per Jaeger's `recommended`-profile retention.

## Reflection

Given the failure scenario above, what's the practical implication for how a team should treat adding a new field to the demo app's span attributes — should attribute additions go through any kind of review, given this lab's redaction model?
