# Lab 14: External Context

Concept background: docs/04-policy-anatomy.md (`context`).

Both examples in this lab stay entirely inside the cluster — no internet dependency in either policy decision, by design.

## ConfigMap context

### 1. Apply the ConfigMap and the policy

```bash
kubectl apply -f demo/namespace.yaml
kubectl apply -f demo/test-resources/approved-environments-configmap.yaml
kubectl apply -f policies/advanced/configmap-context-example.yaml
```

### 2. Test against the ConfigMap's approved list (`lab,staging,production`)

```bash
kubectl run cm-t1 --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="environment=lab"          # pass
kubectl run cm-t2 --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="environment=sandbox-typo"  # fail (reported, this policy is Audit)
kubectl get policyreport -n kyverno-demo | grep validate-environment
```

### 3. Change the approved list and watch behavior change without touching the policy

```bash
kubectl patch configmap kyverno-lab-approved-environments -n kyverno-demo --type merge -p '{"data":{"approvedList":"lab,staging,production,sandbox-typo"}}'
kubectl run cm-t3 --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="environment=sandbox-typo"  # now passes
```

This is the point of externalizing data into context: the *policy* didn't change, only the data it reads.

## Kubernetes API call context

### 1. Apply

```bash
kubectl apply -f policies/advanced/api-call-context-example.yaml
```

### 2. Confirm normal behavior under the limit

```bash
kubectl create deployment api-context-test --image=registry.k8s.io/pause:3.10 -n kyverno-demo
```

Expected: admitted (well under 20 Deployments in `kyverno-demo`).

### 3. Inspect what the context actually resolved to

```bash
kubectl -n kyverno logs -l app.kubernetes.io/component=admission-controller --tail=50 | grep -i limit-deployments
```

The `context.apiCall` here queries `/apis/apps/v1/namespaces/{{request.namespace}}/deployments` live, every time this rule evaluates — see docs/13-performance-and-scaling.md for why this specific pattern (a live API call inside every matching admission request) is the most expensive thing a Kyverno rule can do, and why `operations: ["CREATE"]` narrows it to only new Deployments rather than every update too.

## Cleanup

```bash
kubectl delete -f policies/advanced/configmap-context-example.yaml -f policies/advanced/api-call-context-example.yaml
kubectl -n kyverno-demo delete deployment api-context-test --ignore-not-found
kubectl -n kyverno-demo delete pod cm-t1 cm-t2 cm-t3 --ignore-not-found
kubectl delete -f demo/test-resources/approved-environments-configmap.yaml
```

## Next

`labs/lab-15-jmespath-and-preconditions.md`.
