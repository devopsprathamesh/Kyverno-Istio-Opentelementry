# Lab 03: Required Labels

Concept background: docs/04-policy-anatomy.md (`pattern`), docs/05-validate-policies.md.

## Objective

Require `app.kubernetes.io/name`, `app.kubernetes.io/part-of`, `owner`, `environment` on every Pod, with a clear per-field failure message.

## 1. Apply

```bash
kubectl apply -f policies/validate/require-labels-enforce.yaml
```

## 2. Test failure paths one label at a time

```bash
kubectl run t1 --image=registry.k8s.io/pause:3.10 -n kyverno-demo   # no labels at all -> rejected
kubectl run t2 --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="app.kubernetes.io/name=t2"   # still missing 3 -> rejected
kubectl run t3 --image=registry.k8s.io/pause:3.10 -n kyverno-demo \
  --labels="app.kubernetes.io/name=t3,app.kubernetes.io/part-of=kyverno-learning-lab,owner=platform-team,environment=lab"   # all 4 -> admitted
```

Read the exact rejection message each time — Kyverno's `pattern` mismatch reports which field(s) failed, which is why every policy in this lab writes a specific, actionable `message` rather than a generic "denied."

## 3. Offline equivalent (no cluster needed)

```bash
kyverno test tests/cli-test-cases/require-labels-test.yaml
```

## Common failure to try deliberately

Set one label to an empty string (`app.kubernetes.io/name=""`) — the `?*` pattern anchor requires *non-empty*, so this still fails, distinct from the label being entirely absent. Confirms `?*` semantics concretely rather than just reading about them.

## Cleanup

```bash
kubectl -n kyverno-demo delete pod t1 t2 t3 --ignore-not-found
```

## Next

`labs/lab-04-require-resource-limits.md`.
