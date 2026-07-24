# Jaeger Query Examples

Both the Jaeger UI (`http://127.0.0.1:16686` after `make port-forward-jaeger`) and its underlying HTTP API (what the UI itself calls) are shown — the API form is what `scripts/lib/observability.sh`'s `jaeger_has_traces_for_service`/`jaeger_services` helpers and `tests/traces-test.sh` actually use.

## List known services

```bash
curl -s http://127.0.0.1:16686/api/services | python3 -m json.tool
```
UI: the "Service" dropdown on the Search tab.

## Search traces for one service

```bash
curl -s -G http://127.0.0.1:16686/api/traces --data-urlencode 'service=order-service' --data-urlencode 'limit=20' | python3 -m json.tool
```
UI: select Service = `order-service`, click Find Traces.

## Search by operation (span name)

```bash
curl -s -G http://127.0.0.1:16686/api/traces --data-urlencode 'service=order-service' --data-urlencode 'operation=order.create' | python3 -m json.tool
```
UI: select Service = `order-service`, Operation = `order.create`.

## Search by tag (span attribute)

```bash
curl -s -G http://127.0.0.1:16686/api/traces --data-urlencode 'service=payment-service' --data-urlencode 'tags={"payment.provider":"mock-processor"}' | python3 -m json.tool
```
UI: Tags field, `payment.provider=mock-processor`.

## Search by minimum duration (find slow traces)

```bash
curl -s -G http://127.0.0.1:16686/api/traces --data-urlencode 'service=payment-service' --data-urlencode 'minDuration=500ms' | python3 -m json.tool
```
UI: "Min Duration" field on the Search tab — exactly what `labs/lab-15-sampling.md`'s "keep-slow-traces" tail-sampling policy is meant to guarantee is still findable here even under sampling.

## Fetch one trace by ID

```bash
curl -s "http://127.0.0.1:16686/api/traces/${TRACE_ID}" | python3 -m json.tool
```

## Service dependency graph

```bash
curl -s "http://127.0.0.1:16686/api/dependencies?endTs=$(date +%s%3N)&lookback=3600000" | python3 -m json.tool
```
UI: the "System Architecture" / dependencies view — shows `frontend → order-service → {inventory-service, payment-service}` once enough traces have been collected, a direct visual confirmation of `docs/04-distributed-tracing.md`'s "Service dependency graph".
