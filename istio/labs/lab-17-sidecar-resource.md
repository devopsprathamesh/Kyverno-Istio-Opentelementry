# Lab 17: Sidecar Resource (Egress Scoping)

## Objective

Apply a `Sidecar` resource to `istio-demo`, converting its proxies from "can build config for anything in the mesh registry" to an explicit egress allowlist — and prove both the intended host and, separately, DNS itself depend on getting this scoping right.

## Concepts exercised

`Sidecar` resource egress-host scoping (`../docs/05-traffic-management.md`, `../docs/08-egress-and-serviceentry.md`), why `kube-system/*` must be included for DNS.

## Prerequisites

Labs 01, 03, 16 complete (the `ServiceEntry`-registered simulated external host from Lab 16 is what this lab's `Sidecar` resource explicitly allows).

## Steps

1. **Apply the `Sidecar` resource**:
   ```bash
   kubectl apply -f policies/sidecar/namespace-scoped-sidecar.yaml
   ```
   Inspect it — note the egress hosts list: `istio-demo/*`, `istio-system/*`, `kube-system/*` (DNS), and the specific `istio-external` simulated host from Lab 16.

2. **Confirm the registered external host is still reachable** (explicitly allowed):
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
     http://simulated-external-api.istio-external.svc.cluster.local/
   ```

3. **Confirm an unregistered/unrelated external-looking host is now blocked** — proving the allowlist is real, not decorative:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 \
     http://some-unregistered-host.istio-external.svc.cluster.local/ || echo "blocked/failed as expected"
   ```

4. **Reproduce the DNS gap this repository's own authoring process caught** (`../docs/05-traffic-management.md`): temporarily remove `kube-system/*` from a local copy of the `Sidecar` resource, reapply, and try any DNS-dependent call:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://order-service/ || echo "DNS resolution itself likely broken"
   ```
   CoreDNS lives in `kube-system`, not `istio-system` — an easy namespace to omit when scoping egress, and exactly the mistake this lab's own manifest was caught making (and fixed) during authoring.

5. **Restore the correct manifest**:
   ```bash
   kubectl apply -f policies/sidecar/namespace-scoped-sidecar.yaml
   ```

## Validation

```bash
../tests/egress-test.sh
```
Matches `../tests/expected-results.md`.

## Failure scenarios to notice

Step 4 **is** the failure scenario — confirm you can articulate precisely why removing `kube-system/*` breaks calls to `order-service` (an in-mesh, `istio-demo`-local service) and not just calls to genuinely external hosts: even resolving `order-service.istio-demo.svc.cluster.local`'s IP requires a DNS query to CoreDNS in `kube-system` first, before Envoy ever gets to apply any routing policy at all.

## Cleanup

Leave the correct `Sidecar` resource applied for later labs.

## Reflection

`ServiceEntry` (Lab 16) and `Sidecar`-resource scoping (this lab) are both required together to get the "blocked without registration, reachable with it" behavior described in `../docs/08-egress-and-serviceentry.md`. Explain precisely what each one contributes on its own, and why neither alone produces that behavior.
