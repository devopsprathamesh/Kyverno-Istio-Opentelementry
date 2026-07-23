# Lab 02: Sidecar Injection

## Objective

Observe automatic sidecar injection firsthand, and prove it's driven by the namespace's revision label, not something implicit.

## Concepts exercised

Webhook-based mutating admission injection (`../docs/02-istio-architecture.md`), what injection actually adds to a pod spec — no `istio-init` container in this lab's CNI-plugin model (`../docs/03-envoy-and-sidecar-internals.md`).

## Prerequisites

Lab 01 complete (Istio installed).

## Steps

1. **Create two namespaces — one labeled, one not**:
   ```bash
   kubectl create namespace injection-demo-on
   kubectl label namespace injection-demo-on istio.io/rev=stable-1-30
   kubectl create namespace injection-demo-off
   ```

2. **Run an identical pod in each**:
   ```bash
   kubectl run test-on  -n injection-demo-on  --image=traefik/whoami:v1.11.0 --restart=Never
   kubectl run test-off -n injection-demo-off --image=traefik/whoami:v1.11.0 --restart=Never
   ```

3. **Compare container counts**:
   ```bash
   kubectl get pod test-on  -n injection-demo-on  -o jsonpath='{.spec.containers[*].name}{"\n"}'
   kubectl get pod test-off -n injection-demo-off -o jsonpath='{.spec.containers[*].name}{"\n"}'
   ```
   Expect `whoami istio-proxy` for the first, `whoami` alone for the second.

4. **Confirm there's no init container** (this lab's CNI-plugin interception model):
   ```bash
   kubectl get pod test-on -n injection-demo-on -o jsonpath='{.spec.initContainers[*].name}{"\n"}'
   ```
   Expect empty output — traffic redirection is programmed by the Istio CNI plugin's DaemonSet, not a per-pod init container (`../docs/03-envoy-and-sidecar-internals.md`).

5. **Inspect the injected sidecar's resource requests**:
   ```bash
   kubectl get pod test-on -n injection-demo-on -o jsonpath='{.spec.containers[?(@.name=="istio-proxy")].resources}{"\n"}'
   ```
   Compare against `../install/istiod-values-$LAB_PROFILE.yaml`'s injection defaults.

## Validation

```bash
../tests/sidecar-injection-test.sh
```
Matches `../tests/expected-results.md`'s documented output: injected in the labeled namespace, not injected in the unlabeled one.

## Cleanup

```bash
kubectl delete namespace injection-demo-on injection-demo-off
```

## Reflection

If you label a namespace *after* a pod is already running in it, does that pod get a sidecar retroactively? Why or why not — what has to happen for injection to actually take effect on an existing pod?
