# Lab 04: Envoy Internals Exploration

## Objective

Directly inspect a live Envoy sidecar's listeners, clusters, routes, and endpoints — building the habit of checking proxy ground-truth (`../docs/10-configuration-analysis.md`) rather than only reasoning from applied YAML.

## Concepts exercised

xDS vocabulary (`../docs/01-service-mesh-fundamentals.md`), Envoy ports (`../docs/03-envoy-and-sidecar-internals.md`), `istioctl proxy-config`/`proxy-status`.

## Prerequisites

Lab 03 complete (demo app running).

## Steps

1. **Pick a pod**:
   ```bash
   POD=$(kubectl get pod -n istio-demo -l app=order-service,version=v1 -o jsonpath='{.items[0].metadata.name}')
   ```

2. **Check its sync state first**:
   ```bash
   istioctl proxy-status | grep "$POD"
   ```
   Expect `SYNCED` — if `STALE`, note it and continue (real proxies can transiently show this right after a change; `../docs/14-troubleshooting.md` covers a persistent case).

3. **Dump listeners**:
   ```bash
   istioctl proxy-config listeners "$POD" -n istio-demo
   ```
   Identify the inbound (`15006`-bound) and outbound (`15001`-bound) listeners referenced in `../docs/03-envoy-and-sidecar-internals.md`.

4. **Dump clusters and find `payment-service`'s cluster**:
   ```bash
   istioctl proxy-config clusters "$POD" -n istio-demo | grep payment-service
   ```

5. **Dump that cluster's endpoints**:
   ```bash
   istioctl proxy-config endpoints "$POD" -n istio-demo --cluster "<cluster name from step 4>"
   ```
   Compare the IPs listed against `kubectl get pods -n istio-demo -l app=payment-service -o wide`.

6. **Dump routes**:
   ```bash
   istioctl proxy-config routes "$POD" -n istio-demo
   ```

7. **(Optional, deeper) Port-forward the admin interface directly**:
   ```bash
   kubectl port-forward -n istio-demo "$POD" 15000:15000
   curl -s localhost:15000/stats/prometheus | head -30
   ```
   This is the raw interface `istioctl proxy-config` calls on your behalf — useful when you need a stat `istioctl` doesn't surface directly.

## Validation

You can point to the exact listener, cluster, and endpoint entries backing a specific service call — not just assert the mesh "should" be routing correctly.

## Cleanup

Ctrl-C the port-forward from step 7 if still running; nothing else to clean up.

## Reflection

`istioctl proxy-config clusters` and `endpoints` both show cluster/endpoint information for a *calling* proxy. Why does `../docs/09-resilience-patterns.md` say circuit-breaker settings should be inspected on the caller's proxy, not the destination's — and which of today's commands would you re-run on `frontend`'s pod instead of `order-service`'s to confirm that?
