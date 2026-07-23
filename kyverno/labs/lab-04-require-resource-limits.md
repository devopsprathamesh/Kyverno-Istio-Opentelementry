# Lab 04: Resource Requests and Limits

Concept background: docs/04-policy-anatomy.md (`=()` optional anchor), docs/05-validate-policies.md.

## Objective

Require CPU+memory requests and a memory limit on every `containers`, `initContainers`, and `ephemeralContainers` entry — handling all three, including the ones that may not be present at all.

## 1. Apply

```bash
kubectl apply -f policies/validate/require-resource-limits.yaml
```

## 2. Test each container class

```bash
kubectl apply -f demo/insecure-workloads/deployment-no-resource-limits.yaml -n kyverno-demo
```

Expected: rejected — this fixture has both a `containers` entry and an `initContainers` entry, neither with resources set.

```bash
kubectl apply -f demo/compliant-workloads/deployment-secure-baseline.yaml -n kyverno-demo
```

Expected: admitted — every container sets requests+limits.

## 3. Offline equivalent

```bash
kyverno test tests/cli-test-cases/resource-limits-test.yaml
```

## Why `=(initContainers)` and `=(ephemeralContainers)` specifically

Not every Pod has init or ephemeral containers — the `=()` conditional anchor means "only validate this if the field is present," so a Pod with no `initContainers` at all isn't rejected for "missing" something it was never supposed to have. Compare this to `containers`, which has no `=()` prefix — every Pod has at least one container, so that field is always validated directly. See docs/04-policy-anatomy.md for the full anchor reference.

## Cleanup

```bash
kubectl delete -f demo/insecure-workloads/deployment-no-resource-limits.yaml -n kyverno-demo --ignore-not-found
kubectl delete -f demo/compliant-workloads/deployment-secure-baseline.yaml -n kyverno-demo --ignore-not-found
```

## Next

`labs/lab-05-restrict-privileged-containers.md`.
