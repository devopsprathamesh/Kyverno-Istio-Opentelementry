# curl Commands Reference

Copy-pasteable commands for every UI/API this module exposes, all via `make port-forward-*` (localhost-bound, never public).

## Demo application

```bash
make port-forward-demo &
curl -s -X POST http://localhost:8080/       # triggers the full frontend->order-service->{inventory,payment} chain
curl -s http://localhost:8080/health
```

## Prometheus

```bash
make port-forward-prometheus &
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool
curl -s http://localhost:9090/api/v1/alerts | python3 -m json.tool
```

## Grafana

```bash
make port-forward-grafana &
curl -s -u "admin:$(cat .generated/grafana-admin-password)" http://localhost:3000/api/health
curl -s -u "admin:$(cat .generated/grafana-admin-password)" http://localhost:3000/api/datasources | python3 -m json.tool
curl -s -u "admin:$(cat .generated/grafana-admin-password)" http://localhost:3000/api/search?type=dash-db | python3 -m json.tool
```

## Jaeger

See [`../jaeger/queries/jaeger-api-examples.md`](../jaeger/queries/jaeger-api-examples.md) for the full set.

```bash
make port-forward-jaeger &
curl -s http://localhost:16686/api/services | python3 -m json.tool
```

## Loki

See [`../loki/logql/logql-examples.md`](../loki/logql/logql-examples.md) for the full LogQL set.

```bash
make port-forward-loki &
curl -s http://localhost:13100/ready
```

## Collector (requires a manual port-forward — no dedicated `make` target)

```bash
kubectl -n opentelemetry port-forward svc/otel-collector-gateway 8888:8888 13133:13133 &
curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted
curl -s http://localhost:13133/
```

## Sending test OTLP payloads directly (no SDK needed)

```bash
source scripts/lib/common.sh
source scripts/lib/observability.sh
kubectl -n opentelemetry port-forward svc/otel-collector-gateway 14318:4318 &
send_test_otlp_trace 14318 manual-test-service
send_test_otlp_log 14318 manual-test-service "hello from curl"
```
See [`otlp-client/README.md`](otlp-client/README.md) for the raw, unwrapped version of what these helpers do.
