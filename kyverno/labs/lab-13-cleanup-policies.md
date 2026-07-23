# Lab 13: Cleanup Policies

Concept background: docs/07-generate-and-cleanup-policies.md (Cleanup section), root docs/DECISIONS.md ADR-016.

**Safety reminder**: this policy is scoped, deliberately, to only ever touch Pods labeled `lab-marker: intentionally-insecure` inside `kyverno-demo` — never run a modified version of this lab against a namespace or label selector you haven't reviewed carefully first.

## 1. Apply

```bash
kubectl apply -f policies/cleanup/cleanup-lab-marker-pods.yaml
kubectl -n kyverno-demo get cleanuppolicy cleanup-lab-marker-pods -o yaml
```

Confirm `status.conditions` shows `Ready`.

## 2. Create a marked and an unmarked Pod

```bash
kubectl run cleanup-marked --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="lab-marker=intentionally-insecure"
kubectl run cleanup-unmarked --image=registry.k8s.io/pause:3.10 -n kyverno-demo --labels="app.kubernetes.io/name=cleanup-unmarked"
```

## 3. Confirm the selector, without waiting an hour

```bash
kubectl get pods -n kyverno-demo -l lab-marker=intentionally-insecure
```

This is exactly what the CleanupPolicy's `match` selects — confirm it's ONLY `cleanup-marked`, never `cleanup-unmarked`.

## 4. Observe a real cleanup cycle (optional, requires waiting)

The policy's condition requires the Pod be older than 1 hour, checked every 15 minutes (`schedule: "*/15 * * * *"`). If you want to see a real deletion fire rather than take it on faith:

```bash
# Wait 1h+, then within the next 15-minute window:
kubectl get pods -n kyverno-demo -l lab-marker=intentionally-insecure -w
```

`cleanup-marked` should disappear once both the age condition and schedule align. `cleanup-unmarked` never will, regardless of how long you wait — it doesn't match the selector at all.

## Automated version (does not wait for a real 1h cycle — see the script's own note)

```bash
bash tests/cleanup-policy-tests.sh
```

## Cleanup

```bash
kubectl -n kyverno-demo delete pod cleanup-marked cleanup-unmarked --ignore-not-found
kubectl delete -f policies/cleanup/cleanup-lab-marker-pods.yaml
```

## Next

`labs/lab-14-context-and-api-calls.md`.
