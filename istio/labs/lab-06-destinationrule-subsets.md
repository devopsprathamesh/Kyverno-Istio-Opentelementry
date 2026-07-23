# Lab 06: DestinationRule Subsets

## Objective

Define the `v1`/`v2` subsets that every canary and header-routing `VirtualService` in the following labs depends on, and prove a `VirtualService` referencing an undefined subset fails cleanly.

## Concepts exercised

`DestinationRule` subset definitions, `VirtualService`/`DestinationRule` processing order (`../docs/05-traffic-management.md`).

## Prerequisites

Labs 01, 03 complete.

## Steps

1. **Before applying anything, try to reference a subset that doesn't exist yet** — apply just a canary `VirtualService` with no `DestinationRule` in place:
   ```bash
   kubectl apply -f demo/traffic/virtualservice-canary-90-10.yaml
   istioctl analyze -n istio-demo
   ```
   Expect `analyze` to flag the `v2` (and `v1`) subset references as undefined — exactly the failure mode `../docs/05-traffic-management.md` and `../docs/10-configuration-analysis.md` describe.

2. **Now define the subsets**:
   ```bash
   kubectl apply -f demo/traffic/destinationrule-frontend.yaml
   kubectl apply -f demo/traffic/destinationrule-order-service.yaml
   ```
   Inspect both — note they select on the `version` label (`v1`/`v2`) already present on the demo app's Deployments (Lab 03).

3. **Re-run analyze — confirm it's now clean**:
   ```bash
   istioctl analyze -n istio-demo
   ```

4. **Confirm subset routing now actually works**:
   ```bash
   make -C .. generate-traffic 2>/dev/null || ./scripts/generate-traffic.sh http://order-service.istio-demo.svc.cluster.local 30
   ```
   Note `destinationrule-order-service.yaml` additionally carries `lab-11`/`lab-12` connection-pool and outlier-detection settings — inert until you generate enough concurrent load or failures to trigger them (Labs 11–12), but present here already since `DestinationRule` is the single resource type owning both subset and resilience configuration.

## Validation

`istioctl analyze -n istio-demo` is clean after step 2, and was NOT clean before it — you've directly observed the dependency, not just read about it.

## Failure scenarios to notice

Temporarily change `destinationrule-order-service.yaml`'s `v2` subset selector to a label no pod actually has (e.g., `version: v3`), reapply, and generate traffic — `analyze` stays clean (the subset is defined, just empty), but requests routed to that subset fail at runtime with no healthy endpoints. This is a case `istioctl analyze`'s static checking does **not** catch — you need `istioctl proxy-config endpoints` (`../docs/10-configuration-analysis.md`) to see the subset resolves to zero endpoints. Restore the correct selector afterward.

## Cleanup

Leave both `DestinationRule`s applied — every subsequent traffic-management lab depends on them.

## Reflection

Step 2 of "Failure scenarios" shows a case `istioctl analyze` doesn't catch (a subset defined but matching zero pods) versus Lab 06 step 1's case that it does catch (a subset referenced but not defined at all). Articulate precisely what category of correctness `analyze` verifies, and what category it doesn't — and which tool closes that second gap.
