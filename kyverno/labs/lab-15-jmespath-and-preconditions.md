# Lab 15: JMESPath and Preconditions

Concept background: docs/04-policy-anatomy.md, docs/15-interview-scenarios.md Q26.

## Objective

See `preconditions` gate rule execution across six different dimensions, and understand the evaluation order: `match`/`exclude` → `context` → `preconditions` → the rule's action.

## 1. Apply

```bash
kubectl apply -f policies/advanced/foreach-precondition-jmespath.yaml
```

## 2. Operation type — only fires on CREATE

```bash
kubectl create deployment jmespath-t1 --image=registry.k8s.io/pause:3.10 -n kyverno-demo
kubectl label deployment jmespath-t1 -n kyverno-demo test=1   # an UPDATE — the only-on-create rule's precondition is false here, so it's skipped
kubectl get policyreport -n kyverno-demo -o yaml | grep -B2 -A2 only-on-create
```

## 3. Namespace — only applies inside kyverno-demo

```bash
kubectl create namespace jmespath-elsewhere
kubectl create deployment jmespath-t2 --image=registry.k8s.io/pause:3.10 -n jmespath-elsewhere
```

Expected: admitted with no report entry from `only-in-demo-namespace` — its precondition (`request.namespace == kyverno-demo`) is false outside this lab's demo namespace.

## 4. Replica count — anti-affinity check only above 1 replica

```bash
kubectl scale deployment jmespath-t1 -n kyverno-demo --replicas=1   # precondition false, rule skipped
kubectl scale deployment jmespath-t1 -n kyverno-demo --replicas=3   # precondition true, rule evaluates (and likely fails — jmespath-t1 has no anti-affinity set)
kubectl get policyreport -n kyverno-demo -o yaml | grep -B2 -A2 multi-replica-requires-antiaffinity
```

## 5. Read the skip vs. fail distinction directly

```bash
kubectl get policyreport -n kyverno-demo -o jsonpath='{range .items[*].results[*]}{.rule}{"\t"}{.result}{"\n"}{end}' | sort -u
```

You should see a genuine mix of `pass`, `fail`, and `skip` across this one policy's six rules — `skip` specifically means "precondition false, never evaluated," which is a different signal than `fail` ("evaluated, non-compliant") when you're debugging why a rule "isn't catching" something (docs/15-interview-scenarios.md Q26 walks through exactly this confusion).

## Evaluation order, concretely

`context` resolves first (available to `preconditions` and the action); `preconditions` runs next and can short-circuit the whole rule; only if preconditions pass does the actual `validate`/`mutate`/`generate` logic run. A `context.apiCall` that's expensive but gated behind a `preconditions` check that's false most of the time is far cheaper in aggregate than one with no such gate — worth remembering alongside docs/13-performance-and-scaling.md.

## Cleanup

```bash
kubectl delete -f policies/advanced/foreach-precondition-jmespath.yaml
kubectl -n kyverno-demo delete deployment jmespath-t1 --ignore-not-found
kubectl delete namespace jmespath-elsewhere --wait=false
```

## Next

`labs/lab-16-troubleshooting.md`.
