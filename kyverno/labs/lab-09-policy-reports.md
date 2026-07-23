# Lab 09: Policy Reports

Concept background: docs/10-policy-reports.md.

## Objective

Generate and read `PolicyReport`/`ClusterPolicyReport` data, and see each of the five result states in practice: pass, fail, warn, skip, error.

## 1. Set up a mixed compliant/non-compliant resource set

```bash
kubectl apply -f policies/audit/require-labels-audit.yaml
kubectl apply -f demo/insecure-workloads/pod-missing-labels.yaml     # -> fail
kubectl apply -f demo/compliant-workloads/pod-secure-baseline.yaml   # -> pass
```

## 2. Read the report

```bash
kubectl get policyreport -n kyverno-demo
kubectl describe policyreport -n kyverno-demo
```

Expect both a `pass` entry (for `compliant-secure-baseline`) and a `fail` entry (for `insecure-missing-labels`) within one resync interval.

## 3. Produce a `skip` result

```bash
kubectl apply -f policies/advanced/foreach-precondition-jmespath.yaml
kubectl run skip-demo --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="app.kubernetes.io/name=skip-demo"
kubectl get policyreport -n kyverno-demo -o yaml | grep -B3 -A3 'result: skip'
```

The `only-on-create`/`only-in-demo-namespace` rules in that policy have preconditions — any rule whose precondition doesn't apply shows as `skip`, distinct from `pass`.

## 4. Cluster-wide view

```bash
kubectl get clusterpolicyreports
```

## 5. Summarized

```bash
make reports
```

Runs `scripts/collect-policy-reports.sh` — jq-summarized (if `jq` is installed) failed rules, affected resources, and messages; falls back to raw `kubectl` output otherwise.

## Cleanup

```bash
kubectl delete -f policies/audit/require-labels-audit.yaml -f policies/advanced/foreach-precondition-jmespath.yaml
kubectl -n kyverno-demo delete pod insecure-missing-labels compliant-secure-baseline skip-demo --ignore-not-found
```

## Next

`labs/lab-10-policy-exceptions.md`.
