# Lab 17: Production Readiness

Concept background: docs/11-production-design.md, docs/12-security-and-governance.md, docs/13-performance-and-scaling.md.

## 1. Verify HA configuration is actually in effect

```bash
kubectl -n kyverno get deployment kyverno-admission-controller -o jsonpath='{.spec.replicas}'
kubectl -n kyverno get pdb
kubectl -n kyverno get pods -l app.kubernetes.io/component=admission-controller -o wide
```

With `LAB_PROFILE=recommended`: 2 replicas, a PodDisruptionBudget with `minAvailable: 1`, and (if this cluster has 2+ schedulable workers, which it does) replicas spread across different nodes per the anti-affinity preference.

## 2. Chaos-test it

```bash
kubectl -n kyverno delete pod -l app.kubernetes.io/component=admission-controller --field-selector status.phase=Running | head -1
# immediately, in another terminal:
kubectl run chaos-test --image=registry.k8s.io/pause:3.10 -n kyverno-demo
```

Expected: the `kubectl run` still succeeds (the surviving replica keeps serving) — this is what HA is actually for, demonstrated, not just configured. Compare this against `LAB_PROFILE=minimum` (1 replica) if you want to see the difference directly: a single-replica restart briefly has no admission controller serving at all.

## 3. Production example policies

```bash
kubectl apply -f policies/production-examples/deny-loadbalancer-services.yaml
kubectl apply -f demo/insecure-workloads/service-forbidden-type.yaml -n kyverno-demo
```

Expected: rejected — no LoadBalancer controller exists on this local platform anyway, so this policy also prevents the confusing "stuck Pending forever" state.

```bash
kubectl apply -f policies/production-examples/require-probes-production.yaml
kubectl apply -f demo/applications/demo-web-app.yaml   # no probes set -> reported (Audit mode)
kubectl apply -f demo/compliant-workloads/deployment-secure-baseline.yaml   # has probes -> passes
```

## 4. Governance check

```bash
kubectl get policyexceptions -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.policy-exceptions\.kyverno\.io/expires}{"\n"}{end}'
```

Every active exception should show a real (non-empty, non-past) `expires` date — this is the manual version of the audit check docs/09/docs/11 describe automating.

## 5. Disaster-recovery drill (optional, destructive to the Kyverno install only)

```bash
make uninstall REMOVE_CRDS=false
make install LAB_PROFILE=recommended
make validate-installation
```

Confirms recovery is exactly as fast and reliable as initial install — same commands, same result, per docs/11's Disaster Recovery table.

## Cleanup

```bash
kubectl delete -f policies/production-examples/deny-loadbalancer-services.yaml -f policies/production-examples/require-probes-production.yaml
kubectl -n kyverno-demo delete -f demo/insecure-workloads/service-forbidden-type.yaml -f demo/applications/demo-web-app.yaml -f demo/compliant-workloads/deployment-secure-baseline.yaml --ignore-not-found
kubectl -n kyverno-demo delete pod chaos-test --ignore-not-found
```

## Next

This is the last numbered lab. Return to the root [`README.md`](../README.md) "Next module" section, or root [`docs/LAB-WORKFLOW.md`](../../docs/LAB-WORKFLOW.md) for what comes after the Kyverno lab in this repository's overall sequence.
