# Lab 09: Retries and Timeouts

## Objective

Observe how a route timeout interacts with a fault-injected delay, and prove the timeout cuts off a slow request rather than waiting out the full delay.

## Concepts exercised

`VirtualService` `retries`/`timeout` fields and their interaction (`../docs/09-resilience-patterns.md`).

## Prerequisites

Labs 01, 03 complete.

## Steps

1. **Apply the retry/timeout policy**:
   ```bash
   kubectl apply -f demo/resilience/virtualservice-retries-timeouts.yaml
   ```
   Inspect it — targets `order-service` (subset `v1`) with a 5s overall route `timeout`, 2 retry attempts, a 2s per-try timeout, and `retryOn: "5xx,reset,connect-failure"`.

2. **Baseline: call without any injected delay** — confirm normal calls succeed well within the timeout:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://order-service/
   ```

3. **Construct a temporary delay fault scoped to `order-service`** (the repository's own `demo/resilience/virtualservice-fault-delay.yaml` deliberately targets `inventory-service` instead — Lab 10 uses that one against a different service — so exercising *this* route's timeout means a scoped, disposable copy):
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: networking.istio.io/v1
   kind: VirtualService
   metadata:
     name: order-service-lab09-temp-delay
     namespace: istio-demo
     labels: {app.kubernetes.io/part-of: istio-learning-lab}
   spec:
     hosts: ["order-service"]
     http:
       - fault:
           delay: {percentage: {value: 100.0}, fixedDelay: 4s}
         route:
           - destination: {host: order-service, subset: v1}
   EOF
   ```
   A 4s delay exceeds the 2s per-try timeout but is under the 5s overall timeout — chosen deliberately so you can observe retry behavior, not just an immediate overall-timeout cutoff.

4. **Call again and time it**:
   ```bash
   time kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```
   Expect a `504`. Reason through the timing: each of up to 3 attempts (1 initial + 2 retries) is cut off at its individual 2s per-try timeout, but the *overall* 5s route timeout can't fit all 3 full 2s attempts (6s) — so the total elapsed time should land close to 5s (the overall timeout), not 4s (the injected delay) and not 6s (3 full per-try timeouts).

## Validation

```bash
../tests/retry-timeout-test.sh
```
Matches `../tests/expected-results.md`: response code `504`, elapsed time bounded by the configured timeout, not the full delay.

## Failure scenarios to notice

Remove the `timeout` field from a local copy of `virtualservice-retries-timeouts.yaml` (or `kubectl edit` it temporarily) and repeat step 4 — observe the request now takes much longer (bounded only by per-try timeouts × attempts, or the client's own timeout) since there's no overall route-level ceiling cutting it off early. Restore the field afterward.

## Cleanup

```bash
kubectl delete virtualservice order-service-lab09-temp-delay -n istio-demo
```
Leave `virtualservice-retries-timeouts.yaml` applied if later labs assume it.

## Reflection

This lab's actual values are 2 retries, 2s per-try timeout, 5s overall timeout. Trace through exactly why the observed elapsed time in step 4 lands where it does — why isn't it simply `2s × 3 attempts = 6s`, and why isn't it just the 4s injected delay?
