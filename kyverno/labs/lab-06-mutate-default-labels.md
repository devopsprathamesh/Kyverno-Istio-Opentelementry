# Lab 06: Mutate Default Labels

Concept background: docs/06-mutate-policies.md.

## Objective

Automatically add `environment`, `owner`, `app.kubernetes.io/part-of` to Pods that don't already set them — never overwriting a value that's already present — and understand mutation's relationship to admission ordering.

## 1. Apply

```bash
kubectl apply -f policies/mutate/add-default-labels.yaml
```

## 2. Missing-label case

```bash
kubectl run mutate-t1 --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="app.kubernetes.io/name=mutate-t1"
kubectl get pod mutate-t1 -n kyverno-demo -o jsonpath='{.metadata.labels}'
```

Expected: `environment=lab`, `owner=platform-team`, `app.kubernetes.io/part-of=kyverno-learning-lab` all now present, `app.kubernetes.io/name` unchanged.

## 3. Pre-set value case (the important one)

```bash
kubectl run mutate-t2 --image=registry.k8s.io/pause:3.10 -n kyverno-demo \
  --labels="app.kubernetes.io/name=mutate-t2,environment=production"
kubectl get pod mutate-t2 -n kyverno-demo -o jsonpath='{.metadata.labels.environment}'
```

Expected: `production` — **not** overwritten to `lab`. This is the `+()` addIfNotPresent anchor doing exactly what it's for.

## 4. Deploy the lab's own "real application" and watch it get completed

```bash
kubectl apply -f demo/applications/demo-web-app.yaml
kubectl get deployment demo-web-app -n kyverno-demo -o jsonpath='{.spec.template.metadata.labels}'
```

`demo-web-app.yaml` deliberately only sets `app.kubernetes.io/name` — see its own header comment.

## Automated version

```bash
bash tests/mutate-policy-tests.sh
```

## Admission ordering note

Mutation happens in the mutating-webhook phase, *before* validating webhooks run (docs/01) — so if you also have `policies/validate/require-labels-enforce.yaml` applied, a Pod missing labels can still be **admitted**, because this mutate policy fills them in before the validate policy ever sees the object. Try applying both policies together and creating a labelless Pod to confirm this.

## Cleanup

```bash
kubectl -n kyverno-demo delete pod mutate-t1 mutate-t2 --ignore-not-found
kubectl delete -f demo/applications/demo-web-app.yaml --ignore-not-found
```

## Next

`labs/lab-07-mutate-security-context.md`.
