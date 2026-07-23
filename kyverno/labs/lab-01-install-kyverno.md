# Lab 01: Install and Inspect Kyverno

See docs/02-architecture-and-internals.md for the full architecture behind everything you're about to inspect.

## 1. Install

```bash
make install LAB_PROFILE=recommended
```

This runs `scripts/install.sh`: applies `install/namespace.yaml`, `helm upgrade --install`s the pinned chart (`config/versions.env`) with `install/values-recommended.yaml`, and waits for CRDs, controllers, and webhooks.

## 2. Inspect the Helm release

```bash
helm list -n kyverno
helm get values kyverno -n kyverno
```

## 3. Inspect CRDs

```bash
kubectl get crd | grep kyverno.io
```

Compare against docs/02-architecture-and-internals.md's CRD table — you should see `clusterpolicies.kyverno.io`, `policies.kyverno.io`, `policyexceptions.kyverno.io`, `cleanuppolicies.kyverno.io`, `clustercleanuppolicies.kyverno.io`, `admissionreports.kyverno.io`, `clusteradmissionreports.kyverno.io`, `updaterequests.kyverno.io`, and the CEL-based policy CRDs.

## 4. Inspect controllers

```bash
kubectl -n kyverno get deployments -o wide
kubectl -n kyverno get pods -o wide
```

Four deployments: `kyverno-admission-controller`, `kyverno-background-controller`, `kyverno-cleanup-controller`, `kyverno-reports-controller`. With the `recommended` profile, expect 2 replicas on the admission controller.

## 5. Inspect webhook configurations

```bash
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep kyverno
kubectl get validatingwebhookconfigurations <name> -o yaml   # inspect failurePolicy, rules, namespaceSelector
```

## 6. Inspect RBAC

```bash
kubectl get clusterrole | grep kyverno
kubectl get clusterrolebinding | grep kyverno
```

Notice each controller has its own ServiceAccount/ClusterRole — see docs/02's RBAC section for why.

## 7. Inspect controller logs

```bash
kubectl -n kyverno logs -l app.kubernetes.io/component=admission-controller --tail=50
```

Look for a clean startup with no repeated error/panic lines — this is exactly what `scripts/validate-installation.sh`'s log-scan check automates.

## 8. Full health validation

```bash
make validate-installation
```

Runs every check above programmatically, plus functional probes (a test admission request, an audit report, an enforce rejection, a mutation, a generate) — see `scripts/validate-installation.sh`.

## Expected output (abbreviated)

```text
[PASS] Kubernetes API reachable
[PASS] Namespace 'kyverno' exists
[PASS] Helm release 'kyverno' exists
[PASS] Deployment kyverno-admission-controller available
...
[PASS] validate-installation: all mandatory checks passed.
```

## Next

`labs/lab-02-audit-vs-enforce.md`.
