# Lab 03: Deploying the Demo Application

## Objective

Deploy the full `frontend → order-service → {inventory-service, payment-service}` demo app and confirm every hop works before layering traffic-management/security policy on top in later labs.

## Concepts exercised

Multi-hop east-west service calls (`../docs/01-service-mesh-fundamentals.md`), versioned Deployments as the basis for subset routing (`../docs/05-traffic-management.md`).

## Prerequisites

Lab 01 complete. Lab 02 optional but recommended (understanding injection first makes this lab's `istio-proxy` containers unsurprising).

## Steps

1. **Deploy**:
   ```bash
   make deploy-demo
   ```
   Runs `scripts/deploy-demo.sh` — applies `demo/namespace.yaml` (labeled for injection), `demo/services/{frontend,order-service,inventory-service,payment-service}/`, and `demo/gateway/` (the ingress `Gateway` + a base `VirtualService`, applied together since the gateway is baseline infrastructure, not a per-lab concept). `frontend` and `order-service` each have `v1`/`v2` Deployments; `inventory-service`/`payment-service` have one version each. Traffic/security/resilience/egress policy is deliberately **not** applied here — each later lab applies its own, so you see each concept's effect in isolation.

2. **Confirm every pod has a sidecar**:
   ```bash
   kubectl get pods -n istio-demo -o custom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name
   ```
   Every row should show two containers.

3. **Exercise the full call chain from inside the mesh**:
   ```bash
   kubectl run demo-client -n istio-demo --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 3600
   kubectl exec -n istio-demo demo-client -- curl -s http://frontend/
   kubectl exec -n istio-demo demo-client -- curl -s http://order-service/
   kubectl exec -n istio-demo demo-client -- curl -s http://inventory-service/
   kubectl exec -n istio-demo demo-client -- curl -s http://payment-service/
   ```
   `whoami`'s response body includes its own hostname — confirm you're actually hitting different pods across repeated calls to a versioned service.

4. **Confirm no default-deny policy is blocking this yet** — Lab 03 intentionally runs before Lab 14 (`AuthorizationPolicy`), so every call above should succeed freely at this point.

5. **Confirm the ingress gateway is reachable too** (applied in step 1, but not otherwise exercised in this lab):
   ```bash
   kubectl port-forward -n istio-ingress svc/istio-ingress 8080:80
   ```
   In another terminal: `curl -s http://localhost:8080/` — expect a `frontend` response. Ctrl-C the port-forward when done. See `../examples/application-access.md` for the full access reference and why this lab uses port-forward rather than a `LoadBalancer` IP (`../docs/07-gateways-and-ingress.md`).

## Validation

All four `curl` calls in step 3 return `200`-shaped `whoami` output, no connection errors. Step 5's port-forwarded request also succeeds.

## Cleanup

```bash
kubectl delete pod demo-client -n istio-demo
```
Leave the rest of the demo app deployed — every subsequent lab builds on it. Full teardown is `make clean` (see `lab-20-production-readiness.md`).

## Reflection

At this point, no `Sidecar`, `AuthorizationPolicy`, or `PeerAuthentication` resources exist yet for `istio-demo`. What is actually governing routing and security right now — plain Kubernetes Service behavior, or something Istio is already adding by virtue of the sidecars being present?
