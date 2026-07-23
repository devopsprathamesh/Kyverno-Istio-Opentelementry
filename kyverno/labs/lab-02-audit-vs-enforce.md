# Lab 02: Audit vs. Enforce

Concept background: docs/05-validate-policies.md, root docs/DECISIONS.md ADR-013.

## 1. Deploy the demo namespace and an intentionally non-compliant Pod

```bash
make deploy-demo
kubectl apply -f demo/insecure-workloads/pod-missing-labels.yaml
```

## 2. Apply the audit-mode policy

```bash
kubectl apply -f policies/audit/require-labels-audit.yaml
```

The already-existing `insecure-missing-labels` Pod is untouched (it was admitted before the policy existed) — but wait one resync interval and check the report:

```bash
kubectl get policyreport -n kyverno-demo
kubectl describe policyreport -n kyverno-demo | grep -B2 -A5 insecure-missing-labels
```

Expect a `fail` result entry for that Pod, `result: fail`, with the policy's message — and the Pod is still `Running`. Audit mode never blocks anything.

## 3. Try creating a NEW non-compliant Pod under audit mode

```bash
kubectl run audit-test --image=registry.k8s.io/pause:3.10 -n kyverno-demo
kubectl get pod audit-test -n kyverno-demo   # admitted
```

Still admitted — Audit mode reports at admission time too, it just never denies.

## 4. Switch to enforce mode

```bash
kubectl delete -f policies/audit/require-labels-audit.yaml
kubectl apply -f policies/validate/require-labels-enforce.yaml
```

## 5. Confirm enforcement

```bash
kubectl run enforce-test --image=registry.k8s.io/pause:3.10 -n kyverno-demo
```

Expected: rejected outright, with an error message from the API server quoting Kyverno's policy `message`.

```bash
kubectl run enforce-test-2 --image=registry.k8s.io/pause:3.10 -n kyverno-demo \
  --labels="app.kubernetes.io/name=enforce-test-2,app.kubernetes.io/part-of=kyverno-learning-lab,owner=platform-team,environment=lab"
```

Expected: admitted.

## Automated version

```bash
bash tests/validate-policy-tests.sh
```

## Cleanup

```bash
kubectl delete -f policies/validate/require-labels-enforce.yaml
kubectl -n kyverno-demo delete pod insecure-missing-labels audit-test enforce-test-2 --ignore-not-found
```

## Next

`labs/lab-03-require-labels.md`.
