# Lab 19: Cilium + Istio Troubleshooting (Controlled Failure Scenarios)

## Objective

Run each of `scripts/inject-failures.sh`'s four controlled failure scenarios, recognize each one's symptom, and reverse it — practicing the triage sequence from `../docs/10-configuration-analysis.md`/`../docs/14-troubleshooting.md` against real, if deliberately scoped, breakage.

## Concepts exercised

Cilium `CiliumNetworkPolicy` interacting with Istio's own control/data plane, `AuthorizationPolicy` failure modes, missing-sidecar behavior. Every scenario is reversible via the same script and scoped to `istio-demo` only — never `istio-system`, never a real outage, never touching Cilium's own configuration or `kube-proxy`.

## Prerequisites

Labs 01, 03 complete. Ideally Labs 06, 14, 17 too, so each scenario's mechanism is already familiar from having built it deliberately, once, elsewhere.

## Steps

Run each scenario, observe, then revert before moving to the next — read `scripts/inject-failures.sh` first so you know exactly what each one does before running it.

1. **Scenario: `block-dns`** — a `CiliumNetworkPolicy` denying egress to UDP/TCP port 53 for all of `istio-demo`:
   ```bash
   ./scripts/inject-failures.sh block-dns apply
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://order-service/ || echo "failed as expected"
   ```
   Note this is a **Cilium-layer** (L3/L4) policy, not an Istio resource — `istioctl analyze` won't see it, and it blocks name resolution outright, which then breaks essentially everything downstream of it. Revert:
   ```bash
   ./scripts/inject-failures.sh block-dns revert
   ```

2. **Scenario: `block-istiod`** — a `CiliumNetworkPolicy` denying egress to port `15012` (Istiod's xDS port) for all of `istio-demo`:
   ```bash
   ./scripts/inject-failures.sh block-istiod apply
   ```
   Existing, already-pushed routes keep working (the data plane doesn't need a live control-plane connection for config it already has), but apply a **new** `VirtualService` change now and confirm it never reaches the affected proxies:
   ```bash
   kubectl apply -f demo/traffic/virtualservice-header-routing.yaml
   istioctl proxy-status | grep -i demo
   ```
   Expect proxies in `istio-demo` to show `STALE` rather than `SYNCED` — direct evidence of `../docs/02-istio-architecture.md`'s push/ACK model breaking down when the xDS connection itself is cut, at the Cilium layer, below Istio's own visibility. Revert:
   ```bash
   ./scripts/inject-failures.sh block-istiod revert
   kubectl delete -f demo/traffic/virtualservice-header-routing.yaml
   ```

3. **Scenario: `authz-deny`** — an `AuthorizationPolicy` with `action: DENY` and an empty rule (denies everything to `order-service`):
   ```bash
   ./scripts/inject-failures.sh authz-deny apply
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```
   Expect `403`. Unlike scenarios 1–2, this **is** an Istio-layer resource — confirm `istioctl analyze -n istio-demo` and `kubectl get authorizationpolicy -n istio-demo` immediately surface it, in contrast to the Cilium-layer scenarios above which are invisible to Istio's own tooling. Revert:
   ```bash
   ./scripts/inject-failures.sh authz-deny revert
   ```

4. **Scenario: `missing-sidecar`** — removes `istio-demo`'s injection label:
   ```bash
   ./scripts/inject-failures.sh missing-sidecar apply
   kubectl rollout restart deployment order-service-v1 -n istio-demo
   kubectl rollout status deployment order-service-v1 -n istio-demo
   kubectl get pod -n istio-demo -l app=order-service,version=v1 -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
   ```
   Expect only `whoami`, no `istio-proxy` — a concrete demonstration of what an injection-webhook-relevant misconfiguration looks like operationally. Revert and restore sidecars:
   ```bash
   ./scripts/inject-failures.sh missing-sidecar revert
   kubectl rollout restart deployment order-service-v1 -n istio-demo
   kubectl rollout status deployment order-service-v1 -n istio-demo
   ```

## Validation

For each scenario, you can state: what broke, what the observable symptom was, which `istioctl`/`kubectl` command revealed it, whether it was visible to Istio's own tooling or only at the Cilium layer, and what reversed it.

## Failure scenarios to notice

The meta-lesson: scenarios 1–2 are `CiliumNetworkPolicy` objects — real network-layer enforcement Istio's own `istioctl analyze` has no visibility into at all. A learner who only ever checks Istio-layer tooling (`analyze`, `proxy-status`, `AuthorizationPolicy`) would misdiagnose either of these as an Istio problem when the actual policy lives one layer down, in Cilium. This is precisely why `../docs/14-troubleshooting.md`'s triage table has a dedicated Cilium/CNI-chaining row distinct from the Istio-config rows.

## Cleanup

Confirm every scenario was reverted:
```bash
kubectl get ciliumnetworkpolicy -n istio-demo
kubectl get authorizationpolicy -n istio-demo
kubectl get namespace istio-demo -o jsonpath='{.metadata.labels}'
```
No `lab19-*`-named `CiliumNetworkPolicy`/`AuthorizationPolicy` objects should remain, and `istio.io/rev` should be back on the namespace.

## Reflection

Scenario 2 showed the data plane keeps functioning briefly on already-pushed config even with Istiod's xDS port blocked. `../docs/13-upgrades-and-disaster-recovery.md` and `../docs/02-istio-architecture.md` describe this push/ACK model — what specifically would start failing (and when) if this block were left in place indefinitely, beyond "new config doesn't arrive"? Consider certificate rotation (`../docs/06-service-security-and-mtls.md`) as part of your answer.
