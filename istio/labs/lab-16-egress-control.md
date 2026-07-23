# Lab 16: Egress Control (ServiceEntry)

## Objective

Register a simulated external service via `ServiceEntry`, and observe that Istio's actual default outbound policy is permissive passthrough — registration adds policy/observability applicability, it does not by itself restrict anything.

## Concepts exercised

`ServiceEntry`, Istio's `ALLOW_ANY` default outbound policy (`../docs/08-egress-and-serviceentry.md`). Sidecar-resource-based egress *restriction* is a separate concern — Lab 17.

## Prerequisites

Labs 01, 03 complete.

## Steps

1. **Deploy the simulated external service** — its own namespace, deliberately **not** labeled for sidecar injection, so it behaves like a genuine outside-the-mesh endpoint:
   ```bash
   kubectl apply -f demo/egress/simulated-external-service.yaml
   kubectl -n istio-external wait --for=condition=Ready pod -l app=simulated-external-api --timeout=60s
   ```

2. **Baseline: reach it before any `ServiceEntry` exists** — expect this to work by default (Istio's `ALLOW_ANY` passthrough, `../docs/08-egress-and-serviceentry.md`):
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
     http://simulated-external-api.istio-external.svc.cluster.local/
   ```

3. **Register it formally via `ServiceEntry`**:
   ```bash
   kubectl apply -f demo/egress/serviceentry.yaml
   ```

4. **Confirm Istio-layer policy now applies to this traffic like an in-mesh service** — check that the calling proxy now has a dedicated cluster for it (versus passthrough, which has no dedicated cluster entry):
   ```bash
   istioctl proxy-config clusters demo-client -n istio-demo 2>/dev/null | grep simulated-external || \
     istioctl proxy-config cluster demo-client -n istio-demo --fqdn simulated-external-api.istio-external.svc.cluster.local
   ```

5. **Confirm the call still succeeds, now via the registered entry**:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
     http://simulated-external-api.istio-external.svc.cluster.local/
   ```

## Validation

The call succeeds both before and after registration — the observable difference is in the proxy's own config (step 4), not in whether the call works, which is the point: `ServiceEntry` adds routing/policy applicability, it is not itself an access-control mechanism.

## Failure scenarios to notice

Skip straight to Lab 17's `Sidecar` resource egress scoping without first understanding this lab's point, and you may wrongly conclude "the `ServiceEntry` is what blocks/allows traffic" — it isn't. Confirm this by re-reading step 2: the call succeeded with **no** `ServiceEntry` at all.

## Cleanup

Leave `simulated-external-service.yaml` and `serviceentry.yaml` applied — Lab 17 builds directly on both.

## Reflection

If `ServiceEntry` doesn't restrict egress by itself, what mesh-wide setting *would* convert Istio's default `ALLOW_ANY` posture into default-deny for unregistered hosts globally (`../docs/08-egress-and-serviceentry.md`)? Why might a team choose the narrower, per-namespace `Sidecar`-resource approach (Lab 17) instead of that mesh-wide setting?
