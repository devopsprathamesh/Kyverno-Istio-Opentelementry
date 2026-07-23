# Lab 12: Outlier Detection (Passive Ejection)

## Objective

Distinguish outlier detection from connection-pool circuit breaking (Lab 11) — observe a specific failing endpoint get ejected from the load-balancing pool rather than the whole service being rejected.

## Concepts exercised

`DestinationRule` `trafficPolicy.outlierDetection` (`../docs/09-resilience-patterns.md`).

## Prerequisites

Labs 01, 03, 11 complete (understanding the connection-pool/outlier-detection distinction matters most right after seeing connection-pool behavior directly).

## Steps

1. **Confirm `order-service`'s `DestinationRule` has outlier detection configured**:
   ```bash
   kubectl get destinationrule order-service -n istio-demo -o yaml | grep -A6 outlierDetection
   ```
   Note the consecutive-error threshold and ejection interval.

2. **Make `order-service` fail consistently, scoped directly to it** — the repository's own `virtualservice-fault-abort.yaml` targets `payment-service`, not `order-service`, so exercising `order-service`'s own outlier detection needs a scoped, disposable manifest (same pattern as Lab 09):
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: networking.istio.io/v1
   kind: VirtualService
   metadata:
     name: order-service-lab12-temp-abort
     namespace: istio-demo
     labels: {app.kubernetes.io/part-of: istio-learning-lab}
   spec:
     hosts: ["order-service"]
     http:
       - fault:
           abort: {percentage: {value: 100.0}, httpStatus: 503}
         route:
           - destination: {host: order-service, subset: v1}
   EOF
   ```
   A 100% abort rate makes ejection fast and easy to observe — deliberately more aggressive than the fault-injection labs' realistic percentages, since the goal here is reliably tripping the consecutive-error threshold, not modeling a realistic failure rate.

3. **Generate enough traffic to trip the threshold, then watch endpoint health**:
   ```bash
   ./scripts/generate-traffic.sh http://order-service.istio-demo.svc.cluster.local 20
   POD=$(kubectl get pod -n istio-demo -l app=order-service,version=v1 -o jsonpath='{.items[0].metadata.name}')
   istioctl proxy-config endpoints "$POD" -n istio-demo --cluster "<order-service v1 cluster>" -o json | grep -i health
   ```
   Look for a health status indicating the endpoint was ejected, versus healthy.

4. **Wait past the ejection interval** and re-check — the endpoint should return to the pool for re-evaluation (Istio's outlier detection is not a permanent removal).

## Validation

You can point to a specific moment where a specific endpoint's health status changed from healthy to ejected and back, correlated with the fault-injection window.

## Failure scenarios to notice

Confirm outlier detection is scoped per-**endpoint**, not per-service — with multiple `order-service` v1 replicas, this lab's 100%-abort manifest trips every replica's threshold simultaneously, eventually leaving zero healthy endpoints (a different, more severe outcome than one endpoint being routed around). This distinction matters operationally: outlier detection degrades gracefully only as long as *some* healthy endpoints remain. Try scaling `order-service` v1 to a single replica first, then repeat, to isolate the single-endpoint-ejection case cleanly from the zero-healthy-endpoints case.

## Cleanup

```bash
kubectl delete virtualservice order-service-lab12-temp-abort -n istio-demo
```

## Reflection

Lab 11's connection-pool limit rejects requests when the *aggregate* concurrent load to a service is too high, regardless of which specific endpoint would have served them. This lab's outlier detection instead reacts to one *specific endpoint's* error history. Construct a scenario where a service is unhealthy but neither mechanism would help — what's the gap, and what would close it?
