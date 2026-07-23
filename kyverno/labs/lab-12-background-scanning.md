# Lab 12: Background Scanning

Concept background: docs/03-admission-and-background-processing.md.

## Objective

Directly observe background scanning finding pre-existing, non-compliant resources — and confirm the specific case it does NOT retroactively fix (mutation).

## 1. Create non-compliant resources BEFORE any policy exists

```bash
kubectl run pre-existing-1 --image=registry.k8s.io/pause:3.10 -n kyverno-demo
kubectl run pre-existing-2 --image=nginx:latest -n kyverno-demo
```

## 2. Now apply a validate policy — with `background: true` (the default)

```bash
kubectl apply -f policies/audit/require-labels-audit.yaml
kubectl get clusterpolicy require-labels-audit -o jsonpath='{.spec.background}'
```

## 3. Wait and check the report

```bash
sleep 30
kubectl get policyreport -n kyverno-demo -o yaml | grep -B3 pre-existing-1
```

Expected: within one resync interval, `pre-existing-1` and `pre-existing-2` (both created *before* this policy existed) show up as `fail` in the report — this is background scanning specifically finding resources admission-time evaluation never saw.

## 4. Now the mutation case — apply a mutate policy against the SAME pre-existing resources

```bash
kubectl apply -f policies/mutate/add-default-labels.yaml
sleep 30
kubectl get pod pre-existing-1 -n kyverno-demo -o jsonpath='{.metadata.labels}'
```

Expected: **no new labels added** — `pre-existing-1` was created before this mutate policy existed, and mutate policies (with `background: false`, as this lab's are set — see docs/06) never retroactively touch resources. Compare directly against a NEW Pod created after the policy:

```bash
kubectl run post-existing-1 --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="app.kubernetes.io/name=post-existing-1"
kubectl get pod post-existing-1 -n kyverno-demo -o jsonpath='{.metadata.labels}'
```

Expected: default labels present — this one went through admission-time mutation normally.

## Cases that are NOT mutated retroactively

Every `validate` failure background scanning finds requires a separate remediation action (fix the resource, or a `mutate-existing`-configured rule if you've deliberately opted into that — this lab doesn't). There is no "apply background scan results" button.

## Cleanup

```bash
kubectl -n kyverno-demo delete pod pre-existing-1 pre-existing-2 post-existing-1 --ignore-not-found
kubectl delete -f policies/audit/require-labels-audit.yaml -f policies/mutate/add-default-labels.yaml
```

## Next

`labs/lab-13-cleanup-policies.md`.
