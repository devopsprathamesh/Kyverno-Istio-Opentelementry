# Lab 11: Circuit Breaking (Connection Pool Limits)

## Objective

Drive concurrent load past a configured connection-pool limit and observe Envoy reject the overflow — the "circuit breaker" behavior in the classic sense.

## Concepts exercised

`DestinationRule` `trafficPolicy.connectionPool` (`../docs/09-resilience-patterns.md`), why this is evaluated on the *calling* proxy.

## Prerequisites

Labs 01, 03 complete.

## Steps

1. **Apply the connection-pool-limited `DestinationRule`**:
   ```bash
   kubectl apply -f demo/traffic/destinationrule-order-service.yaml
   ```
   Inspect its `connectionPool` settings — note the concurrent connection/request limits.

2. **Drive concurrent load exceeding the limit**:
   ```bash
   for i in $(seq 1 30); do
     kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/ &
   done
   wait
   ```
   (Or use `./scripts/generate-traffic.sh http://order-service.istio-demo.svc.cluster.local 30 30` — `TARGET_URL REQUEST_COUNT CONCURRENCY` as positional args; see `scripts/generate-traffic.sh`.)

3. **Tally the response codes** — expect a mix of `200`s (succeeded) and `5xx`s (rejected by the pool limit, an Envoy-generated response, not from `whoami` itself).

4. **Confirm the rejection is from Envoy, not the backend** — check `istio-proxy` container logs on the frontend/client side vs. `order-service`'s `whoami` container logs; the rejected requests should never appear in `whoami`'s own access log.

## Validation

```bash
../tests/circuit-breaking-test.sh
```
Matches `../tests/expected-results.md`. A `[WARN]` (no overflow observed) is explicitly documented as possible and non-fatal — `whoami` responds fast enough that a small test load may not saturate the pool; if you see this, increase `COUNT`/concurrency and retry.

## Failure scenarios to notice

Run the same concurrent load test *without* the `DestinationRule`'s connection-pool limits applied (temporarily delete it) and compare — expect all (or nearly all) requests to succeed, confirming the pool limit, not backend capacity, was what produced the earlier rejections.

## Cleanup

Reapply `demo/traffic/destinationrule-order-service.yaml` if you removed it for the comparison in the failure scenario above.

## Reflection

Why does `../docs/09-resilience-patterns.md` say connection-pool rejections happen "at the calling sidecar," not at the destination? If you ran `istioctl proxy-config clusters` on `order-service`'s own pod (the destination) during this test, would you expect to see evidence of the rejection there? Why or why not?
