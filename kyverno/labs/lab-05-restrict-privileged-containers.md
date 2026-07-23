# Lab 05: Restrict Privileged Workloads

Concept background: docs/04-policy-anatomy.md (`X()` anchor, `foreach`+`deny`), docs/12-security-and-governance.md (Kyverno vs. PSA overlap).

## Objective

Reject `privileged: true`, host namespaces (network/PID/IPC), dangerous added capabilities, and hostPath volumes — four independent rules, one policy.

## 1. Apply

```bash
kubectl apply -f policies/validate/restrict-privileged-containers.yaml
```

## 2. Exercise each rule against its matching fixture

```bash
for f in pod-privileged pod-host-namespaces pod-hostpath-volume pod-dangerous-capabilities; do
  echo "--- ${f} ---"
  kubectl apply -f "demo/insecure-workloads/${f}.yaml" || true
done
```

Every one of these should be **rejected**, each with a message naming the specific rule that fired.

```bash
kubectl apply -f demo/compliant-workloads/pod-secure-baseline.yaml
```

Expected: admitted — no privileged flag, no host namespaces, no hostPath, no dangerous capabilities.

## 3. Offline equivalent

```bash
kyverno test tests/cli-test-cases/privileged-containers-test.yaml
```

## 4. Overlap with Pod Security Admission

```bash
kubectl label namespace kyverno-demo pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl apply -f demo/insecure-workloads/pod-privileged.yaml
kubectl label namespace kyverno-demo pod-security.kubernetes.io/enforce=privileged --overwrite   # revert — this lab's default
```

With PSA `restricted` also active, the same rejected Pod may now fail at the PSA layer *before* Kyverno's webhook is even reached (PSA runs as part of core admission, ahead of custom webhooks in practice) — read the actual denial message to see which layer caught it. Revert the namespace label afterward; this lab's default keeps PSA out of the way specifically so Kyverno's own rejections are the ones being demonstrated (see `demo/namespace.yaml`'s comment).

## Cleanup

```bash
kubectl -n kyverno-demo delete pod compliant-secure-baseline --ignore-not-found
```

(The four insecure fixtures were rejected, so nothing to clean up for them.)

## Next

`labs/lab-06-mutate-default-labels.md`.
