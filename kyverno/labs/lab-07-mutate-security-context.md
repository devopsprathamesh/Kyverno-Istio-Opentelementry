# Lab 07: Mutate Security Context

Concept background: docs/06-mutate-policies.md, docs/04-policy-anatomy.md (`foreach` + `patchStrategicMerge`).

## Objective

Add `runAsNonRoot`, `allowPrivilegeEscalation: false`, a `RuntimeDefault` seccomp profile, and dropped `ALL` capabilities — only where those fields are absent, at both Pod and per-container level.

## 1. Apply

```bash
kubectl apply -f policies/mutate/add-security-context-defaults.yaml
```

## 2. No securityContext at all

```bash
kubectl run secctx-t1 --image=registry.k8s.io/pause:3.10 -n kyverno-demo
kubectl get pod secctx-t1 -n kyverno-demo -o jsonpath='{.spec.securityContext}{"\n"}{.spec.containers[0].securityContext}'
```

Expected: Pod-level `runAsNonRoot: true` + seccompProfile added; container-level `allowPrivilegeEscalation: false` + `capabilities.drop: ["ALL"]` added.

## 3. Intentional exception, not fought by mutation

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secctx-t2
  namespace: kyverno-demo
  labels: {app.kubernetes.io/name: secctx-t2}
spec:
  securityContext:
    runAsNonRoot: false
  containers:
    - name: app
      image: registry.k8s.io/pause:3.10
      resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {memory: 32Mi}}
EOF
kubectl get pod secctx-t2 -n kyverno-demo -o jsonpath='{.spec.securityContext.runAsNonRoot}'
```

Expected: `false` — left exactly as the Pod spec intentionally set it. This is the doc's central point made concrete: mutation never overrides an explicit, intentional choice, even a "worse" one. A Pod that genuinely needs `runAsNonRoot: false` (rare, but real — some legacy images require it) should express that explicitly and, if it also needs to bypass a *validate* policy that would otherwise reject it, use PolicyException (labs/lab-10), not fight a mutation policy.

## Cleanup

```bash
kubectl -n kyverno-demo delete pod secctx-t1 secctx-t2 --ignore-not-found
```

## Next

`labs/lab-08-generate-network-policy.md`.
