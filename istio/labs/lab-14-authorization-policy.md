# Lab 14: Authorization Policy

## Objective

Establish default-deny for `istio-demo`, then open exactly the paths the demo app needs — proving identity-based, not IP-based, enforcement.

## Concepts exercised

Default-deny + explicit allow (`../docs/06-service-security-and-mtls.md`), SPIFFE-identity-based `AuthorizationPolicy` matching, method/path restriction.

## Prerequisites

Labs 01, 03, 13 complete (strict mTLS gives authorization policy real identity to match against).

## Steps

1. **Baseline: confirm calls succeed with no `AuthorizationPolicy` yet**:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```

2. **Apply default-deny** (`policies/authorization/namespace-default-deny.yaml` — step 1: an `AuthorizationPolicy` with no `selector` and no `rules` denies all traffic to every workload in the namespace):
   ```bash
   kubectl apply -f policies/authorization/namespace-default-deny.yaml
   ```

3. **Confirm everything is now denied, including legitimate calls**:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```
   Expect `403` — this is the intended "fail closed" starting point.

4. **Open the specific allowed paths** (step 2: principal-matched explicit allows):
   ```bash
   kubectl apply -f policies/authorization/allow-frontend-to-order.yaml
   kubectl apply -f policies/authorization/allow-order-to-downstream.yaml
   ```

5. **Confirm the demo app's actual call chain works again, end to end** — from `frontend`'s ServiceAccount identity specifically, not `demo-client`'s (which has no matching allow rule):
   ```bash
   FRONTEND_POD=$(kubectl get pod -n istio-demo -l app=frontend,version=v1 -o jsonpath='{.items[0].metadata.name}')
   kubectl exec -n istio-demo "$FRONTEND_POD" -c istio-proxy -- curl -s http://order-service/
   ```

6. **Confirm `demo-client` (no matching identity) is still denied** — proving this is identity-based, not "any in-mesh pod":
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```
   Expect `403` still.

7. **Apply the advanced method/path restriction** (`method-path-restriction.yaml` — narrows `order-service`'s already-allowed access to `payment-service` down to specific methods/paths):
   ```bash
   kubectl apply -f policies/authorization/method-path-restriction.yaml
   ```

## Validation

```bash
../tests/authorization-test.sh
```
Matches `../tests/expected-results.md`: unauthorized caller denied; a different non-frontend in-mesh identity also denied.

## Failure scenarios to notice

Edit a local copy of `allow-frontend-to-order.yaml` to remove its `principals`/`source` restriction entirely (an empty `from` match) and reapply — observe `demo-client` now succeeds too. A concrete demonstration of how easy it is to accidentally widen an allow rule beyond intent, and why reviewing the exact `principals` field matters, not just that a policy named "allow-frontend..." exists. Restore the original file afterward.

## Cleanup

Leave default-deny and the allow policies applied — later labs assume this posture.

## Reflection

`demo-client` is a legitimate in-mesh, sidecar-injected pod with a valid mTLS certificate — yet it's denied. Explain precisely why mTLS succeeding (Lab 13) and authorization succeeding (this lab) are two separate, independently-enforced questions, using the SPIFFE identity concept from `../docs/06-service-security-and-mtls.md`.
