# Lab 13: Strict mTLS

## Objective

Migrate `istio-demo` from permissive to strict mTLS, and prove a plaintext (non-mesh) client is rejected while in-mesh callers are unaffected.

## Concepts exercised

`PeerAuthentication` permissive vs. strict (`../docs/06-service-security-and-mtls.md`), SPIFFE-issued workload certificates.

## Prerequisites

Labs 01, 03 complete.

## Steps

1. **Start permissive** (`policies/peerauthentication/permissive.yaml` — step 1 of this lab's own manifests; also Istio's mesh-wide default even with no `PeerAuthentication` at all, applied explicitly here so the state is visible):
   ```bash
   kubectl apply -f policies/peerauthentication/permissive.yaml
   ```

2. **Confirm an in-mesh call succeeds**:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```

3. **Confirm a plaintext, non-mesh call also currently succeeds** (permissive accepts both):
   ```bash
   kubectl run plaintext-client -n istio-demo --image=curlimages/curl:8.10.1 --restart=Never \
     --annotations="sidecar.istio.io/inject=false" --command -- sleep 3600
   kubectl exec -n istio-demo plaintext-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```

4. **Switch to strict** (`policies/peerauthentication/strict.yaml` — named `default`, same as `permissive.yaml`, so applying it replaces rather than adds to the permissive policy):
   ```bash
   kubectl apply -f policies/peerauthentication/strict.yaml
   ```

5. **Re-test both clients**:
   ```bash
   kubectl exec -n istio-demo demo-client      -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://order-service/
   kubectl exec -n istio-demo plaintext-client -- curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://order-service/ || echo "rejected as expected"
   ```
   Expect the in-mesh client to still succeed and the plaintext client to now fail/hang/reject.

## Validation

```bash
../tests/mtls-test.sh
```
Matches `../tests/expected-results.md`: in-mesh client succeeds, plaintext client correctly rejected under `STRICT`.

## Failure scenarios to notice

Switch straight to strict on a namespace where you know at least one workload lacks a sidecar (`plaintext-client` itself) and note this is exactly the "rolling out strict mTLS too early" failure mode `../docs/06-service-security-and-mtls.md` warns about — in a real migration, you'd confirm 100% sidecar coverage before flipping to strict, not after.

## Cleanup

```bash
kubectl delete pod plaintext-client -n istio-demo
kubectl apply -f policies/peerauthentication/permissive.yaml
```
Reset to permissive so later labs (which don't specifically test mTLS mode) aren't affected by strict mode's stricter default.

## Reflection

The plaintext client's rejection happens at the *transport* layer, before any `AuthorizationPolicy` (Lab 14) is even evaluated. Why does that ordering make sense — what would be the security implication of evaluating authorization *before* confirming the caller's identity is genuine?
