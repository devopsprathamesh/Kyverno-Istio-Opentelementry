# Lab 10: Fault Injection

## Objective

Deliberately break traffic — inject delays and aborts — to test resilience configuration without needing an application that can actually fail on demand.

## Concepts exercised

`VirtualService` fault injection (`../docs/09-resilience-patterns.md`), why this lab uses Istio's own fault injection rather than custom application code (root `docs/DECISIONS.md`).

## Prerequisites

Labs 01, 03 complete.

## Steps

1. **Abort injection** (targets `payment-service`, 30% of requests, HTTP 503):
   ```bash
   kubectl apply -f demo/resilience/virtualservice-fault-abort.yaml
   ```
   Inspect the file — note the abort percentage and status code.

2. **Generate traffic against `payment-service` and tally outcomes**:
   ```bash
   ./scripts/generate-traffic.sh http://payment-service.istio-demo.svc.cluster.local 50
   ```
   Expect roughly 30% of requests to return `503`, the rest to succeed normally.

3. **Remove the abort fault, apply delay injection instead** (targets `inventory-service`, 50% of requests, 3s fixed delay — a different destination, deliberately, so you can attribute each behavior to a distinct service):
   ```bash
   kubectl delete -f demo/resilience/virtualservice-fault-abort.yaml
   kubectl apply -f demo/resilience/virtualservice-fault-delay.yaml
   ```

4. **Time individual requests against `inventory-service`** to observe the delay directly:
   ```bash
   time kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null http://inventory-service/
   ```
   Run a few times — roughly half should show the ~3s injected delay, the rest (outside the configured 50%) should return immediately.

## Validation

```bash
../tests/fault-injection-test.sh
```
Matches `../tests/expected-results.md`: observed abort rate within statistical tolerance of the configured percentage.

## Failure scenarios to notice

Both faults in this repository target different services (`payment-service` for abort, `inventory-service` for delay) specifically so each behavior is independently attributable. Construct (using the same pattern as Lab 09's temporary manifest) a single `VirtualService` with **both** `abort` and `delay` under the same `fault:` block, targeting one service, and observe how Envoy applies them — check the Istio API reference for whether `abort` and `delay` on the same `HTTPFaultInjection` are independent probabilities or mutually exclusive, then confirm which behavior you actually observe. Delete your temporary manifest afterward.

## Cleanup

```bash
kubectl delete -f demo/resilience/virtualservice-fault-delay.yaml
kubectl delete -f demo/resilience/virtualservice-fault-abort.yaml 2>/dev/null || true
```

## Reflection

Why is fault injection entirely an Envoy-layer feature that never touches the `whoami` backend at all? What's the pedagogical argument (made in root `docs/DECISIONS.md`) for testing Istio's resilience features this way rather than building an application that can be told to fail?
