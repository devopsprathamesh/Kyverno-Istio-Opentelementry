# curl Test Commands Reference

Single-shot, copy-pasteable `curl` invocations used across the lab series, grouped by concept. All assume a `demo-client` pod exists in `istio-demo` (see [`application-access.md`](application-access.md)) unless noted otherwise. Full walkthroughs with expected output live in the referenced lab files — this is a quick lookup, not a replacement for them.

## Basic reachability

```bash
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
```

## Timing a request

```bash
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' http://order-service/
```

## Header-based routing ([`../labs/lab-08-header-based-routing.md`](../labs/lab-08-header-based-routing.md))

```bash
kubectl exec -n istio-demo demo-client -- curl -s -H "x-canary-user: true" http://frontend/ | grep -i hostname
```

## Path-based routing ([`../labs/lab-05-virtualservice-routing.md`](../labs/lab-05-virtualservice-routing.md))

```bash
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/<exact-path-from-manifest>
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/<prefix>/anything
```

## JWT authentication ([`../labs/lab-15-jwt-authentication.md`](../labs/lab-15-jwt-authentication.md))

```bash
# No token — denied by AuthorizationPolicy default-deny
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/

# Invalid token — denied by RequestAuthentication itself
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer not-a-real-token" http://order-service/

# Valid token
TOKEN="$(cat .generated/jwt/token.txt)"
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer ${TOKEN}" http://order-service/
```

## mTLS verification ([`../labs/lab-13-strict-mtls.md`](../labs/lab-13-strict-mtls.md))

```bash
# From a sidecar-injected pod (should succeed under STRICT)
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://order-service/

# From a pod explicitly excluded from injection (should fail under STRICT)
kubectl run plaintext-client -n istio-demo --image=curlimages/curl:8.10.1 --restart=Never \
  --annotations="sidecar.istio.io/inject=false" --command -- sleep 3600
kubectl exec -n istio-demo plaintext-client -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://order-service/
```

## Egress ([`../labs/lab-16-egress-control.md`](../labs/lab-16-egress-control.md), [`../labs/lab-17-sidecar-resource.md`](../labs/lab-17-sidecar-resource.md))

```bash
# Registered + allowed
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
  http://simulated-external-api.istio-external.svc.cluster.local/

# Unregistered — should be blocked once Sidecar-resource scoping is applied
kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 \
  http://some-unregistered-host.istio-external.svc.cluster.local/
```

## Ingress gateway ([`application-access.md`](application-access.md), [`../labs/lab-03-deploying-demo-app.md`](../labs/lab-03-deploying-demo-app.md))

```bash
# Requires: kubectl port-forward -n istio-ingress svc/istio-ingress 8080:80 (separate terminal)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/
```

## Bulk/statistical requests

Prefer [`../scripts/generate-traffic.sh`](../scripts/generate-traffic.sh) over a manual loop for anything measuring a distribution (canary weights, fault-injection rates) — it tallies response codes/hostnames for you:

```bash
./scripts/generate-traffic.sh http://order-service.istio-demo.svc.cluster.local 100 10
```
