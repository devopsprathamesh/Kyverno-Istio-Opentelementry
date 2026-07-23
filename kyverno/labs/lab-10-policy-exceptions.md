# Lab 10: Policy Exceptions

Concept background: docs/09-policy-exceptions.md.

## Objective

Create and validate a narrowly-scoped `PolicyException`, and confirm it does NOT accidentally widen to cover other resources.

## 1. Apply the underlying policy and the exception

```bash
kubectl apply -f policies/validate/restrict-privileged-containers.yaml
kubectl apply -f policies/exceptions/allow-demo-hostpath-exception.yaml
```

## 2. The exempted resource is admitted

```bash
kubectl apply -f demo/test-resources/demo-approved-hostpath-reader.yaml
kubectl get pod demo-approved-hostpath-reader -n kyverno-demo
```

Expected: `Running` — despite using a hostPath volume, which `restrict-privileged-containers`'s `disallow-hostpath-volumes` rule would otherwise reject.

## 3. A DIFFERENT resource with the same pattern is still rejected

```bash
kubectl apply -f demo/insecure-workloads/pod-hostpath-volume.yaml
```

Expected: rejected. Same hostPath pattern, different resource name — the exception's `match.any.resources.names` list is exact, not a pattern match.

## 4. Every OTHER rule still applies to the exempted resource

```bash
kubectl run priv-check -n kyverno-demo --image=registry.k8s.io/pause:3.10 \
  --overrides='{"metadata":{"name":"demo-approved-hostpath-reader-priv-test"},"spec":{"containers":[{"name":"app","image":"registry.k8s.io/pause:3.10","securityContext":{"privileged":true}}]}}' \
  --dry-run=server -o yaml 2>&1 | tail -5
```

Expected: rejected by the `disallow-privileged` rule — the exception only named `disallow-hostpath-volumes`, so privileged-container protection is fully intact for this same resource name too (the exception matched by name, but only exempts the one rule it explicitly listed).

## 5. Inspect the exception's governance annotations

```bash
kubectl get policyexception allow-demo-hostpath-exception -n kyverno-demo -o yaml | grep -A5 annotations
```

Note `policy-exceptions.kyverno.io/expires`, `approved-by`, `ticket` — a documented convention this lab uses, not something Kyverno itself enforces (docs/09's "Expiration and approval process"). In a real deployment, a scheduled check or GitOps CI gate would fail/alert on an exception whose `expires` date has passed; nothing here does that automatically — it's a process you'd build, not a Kyverno feature.

## Automated version

```bash
bash tests/exception-tests.sh
```

## Cleanup

```bash
kubectl delete -f policies/exceptions/allow-demo-hostpath-exception.yaml -f policies/validate/restrict-privileged-containers.yaml
kubectl -n kyverno-demo delete pod demo-approved-hostpath-reader --ignore-not-found
```

## Next

`labs/lab-11-image-verification.md`.
