# Application Access

How to reach the demo app and its individual services, both from outside the mesh and from inside it. This lab never exposes anything via a cloud `LoadBalancer` or a host-bound port by default — see [`../docs/07-gateways-and-ingress.md`](../docs/07-gateways-and-ingress.md) and root [`docs/DECISIONS.md`](../../docs/DECISIONS.md) ADR-023 for why.

## From outside the mesh — through the ingress gateway

```bash
kubectl port-forward -n istio-ingress svc/istio-ingress 8080:80
```

Then, in another terminal:

```bash
curl -s http://localhost:8080/
```

This reaches `frontend` via the `Gateway`/`VirtualService` applied in [`../demo/gateway/`](../demo/gateway/) (applied automatically by `make deploy-demo` — see [`../labs/lab-03-deploying-demo-app.md`](../labs/lab-03-deploying-demo-app.md)). If you've applied [`../labs/lab-08-header-based-routing.md`](../labs/lab-08-header-based-routing.md)'s manifest, add `-H "x-canary-user: true"` to reach `v2`. If you've applied path-based routing from [`../labs/lab-05-virtualservice-routing.md`](../labs/lab-05-virtualservice-routing.md), that lab targets `order-service` directly rather than through the gateway — see its own steps.

## From inside the mesh — direct service calls

```bash
kubectl run demo-client -n istio-demo --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 3600
kubectl exec -n istio-demo demo-client -- curl -s http://frontend/
kubectl exec -n istio-demo demo-client -- curl -s http://order-service/
kubectl exec -n istio-demo demo-client -- curl -s http://inventory-service/
kubectl exec -n istio-demo demo-client -- curl -s http://payment-service/
```

Most labs from [`../labs/lab-03-deploying-demo-app.md`](../labs/lab-03-deploying-demo-app.md) onward assume a `demo-client` pod like this exists in `istio-demo` — recreate it if you cleaned it up between labs.

## Generating repeated/bulk traffic

```bash
./scripts/generate-traffic.sh http://frontend.istio-demo.svc.cluster.local 100 10
```
Positional args: `TARGET_URL REQUEST_COUNT CONCURRENCY` (all optional — defaults to `frontend`, `config/lab-settings.env`'s `TRAFFIC_DEFAULT_REQUESTS`/`TRAFFIC_DEFAULT_CONCURRENCY`). Prints a response-code/hostname distribution summary — used throughout the canary/header-routing labs. See [`curl-test-commands.md`](curl-test-commands.md) for single-shot, more targeted `curl` invocations (specific headers, specific paths, timing).

## Reading a live proxy directly

```bash
POD=$(kubectl get pod -n istio-demo -l app=order-service,version=v1 -o jsonpath='{.items[0].metadata.name}')
istioctl proxy-config listeners "$POD" -n istio-demo
istioctl proxy-config routes    "$POD" -n istio-demo
istioctl proxy-config clusters  "$POD" -n istio-demo
```
See [`../labs/lab-04-envoy-internals-exploration.md`](../labs/lab-04-envoy-internals-exploration.md) and [`../docs/10-configuration-analysis.md`](../docs/10-configuration-analysis.md).

## Quick status glance

```bash
make status
```
Runs [`../scripts/status.sh`](../scripts/status.sh) — a fast, read-only snapshot of the control plane, ingress gateway, demo app, and proxy-sync state.
