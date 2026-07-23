# Lab 16: Troubleshooting

Concept background: docs/14-troubleshooting.md — this lab deliberately introduces controlled failures so you diagnose them yourself before ever needing to under real pressure.

## 1. Invalid policy syntax

```bash
cat <<'EOF' > /tmp/broken-policy.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: broken-policy
spec:
  rules:
    - name: broken-rule
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "broken"
        pattern:
          metadata:
            labels:
              this-is-not-closed: [
EOF
kubectl apply -f /tmp/broken-policy.yaml
```

Expected: rejected at `kubectl apply` time (invalid YAML) — the fastest possible failure, before Kyverno is even involved. Fix by validating with `kyverno apply`/`kyverno test`, or a plain YAML linter, before ever running `kubectl apply` on a hand-edited policy.

## 2. Policy stuck NotReady

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: notready-policy
spec:
  rules:
    - name: bad-kind
      match:
        any:
          - resources:
              kinds: ["ThisKindDoesNotExist"]
      validate:
        message: "unreachable"
        pattern:
          metadata:
            labels:
              x: "?*"
EOF
kubectl get clusterpolicy notready-policy -o jsonpath='{.status}'
kubectl delete clusterpolicy notready-policy
```

Expected: `status.ready` false or a condition explaining the unresolvable kind — this is the diagnostic path for "why won't my policy activate."

## 3. Incorrect match / exclude rule

```bash
kubectl apply -f policies/validate/require-labels-enforce.yaml
kubectl patch clusterpolicy require-labels-enforce --type=json \
  -p='[{"op":"replace","path":"/spec/rules/0/match/any/0/resources/kinds/0","value":"ConfigMap"}]'
kubectl run match-fail-test --image=registry.k8s.io/pause:3.10 -n kyverno-demo
```

Expected: admitted — the policy now matches `ConfigMap`, not `Pod`, so it silently stops protecting what you thought it protected. Revert:

```bash
kubectl apply -f policies/validate/require-labels-enforce.yaml   # restores kinds: ["Pod"]
```

This is deliberately the most common real-world "policy isn't working" root cause — always check `match`/`exclude` FIRST, per docs/14's decision tree.

## 4. Permission denied (simulated RBAC gap)

```bash
kubectl -n kyverno logs -l app.kubernetes.io/component=background-controller --tail=100 | grep -i forbidden || echo "no RBAC errors currently — expected in a healthy install"
```

In a real incident, a `forbidden`/`cannot ...` log line here is your signal — see docs/14's "Insufficient RBAC" row for the fix pattern (extend the specific controller's ClusterRole narrowly, never broadly).

## 5. Exception too broad (a deliberately bad example — do not keep this)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v2
kind: PolicyException
metadata:
  name: lab16-too-broad-example
  namespace: kyverno-demo
spec:
  exceptions:
    - policyName: require-labels-enforce
      ruleNames: ["check-required-labels"]
  match:
    any:
      - resources:
          kinds: ["Pod"]
          namespaces: ["kyverno-demo"]
EOF
kubectl run exception-too-broad-test --image=registry.k8s.io/pause:3.10 -n kyverno-demo
kubectl delete policyexception lab16-too-broad-example -n kyverno-demo
```

Notice: no `names` restriction means this exempts **every** Pod in the namespace, not one — exactly the anti-pattern docs/09 and root docs/DECISIONS.md ADR-016 warn against. Compare directly against `policies/exceptions/allow-demo-hostpath-exception.yaml`'s explicit `names` list.

## Cleanup

```bash
kubectl delete -f policies/validate/require-labels-enforce.yaml
kubectl -n kyverno-demo delete pod match-fail-test exception-too-broad-test --ignore-not-found
rm -f /tmp/broken-policy.yaml
```

## Next

`labs/lab-17-production-readiness.md`.
