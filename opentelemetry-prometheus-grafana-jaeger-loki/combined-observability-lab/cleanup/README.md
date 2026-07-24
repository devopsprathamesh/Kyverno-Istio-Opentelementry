# Cleanup

Scoped teardown for this capstone — identical to the module's own cleanup targets, since this lab installs nothing beyond what `make install-all`/`make deploy-demo` already does.

## Remove just the demo app and lab-applied config (backends stay up)

```bash
cd ..   # module root
make clean
```
Use this if you want to re-run [`../scenarios/incident-workflow.md`](../scenarios/incident-workflow.md) fresh without reinstalling the whole stack.

## Full teardown

```bash
make uninstall-all
```
Read the printed `[WARN]` first — removes every Helm release and the Collector's raw manifests. CRDs kept unless `REMOVE_CRDS=true`. Never touches Cilium, kube-proxy, or any other module — see [`../../labs/lab-21-production-readiness.md`](../../labs/lab-21-production-readiness.md) for the full teardown-verification checklist.

## Confirm scope after either cleanup

```bash
kubectl get daemonset -n kube-system cilium kube-proxy
kubectl get namespace kyverno istio-system 2>&1   # expect: not found, or pre-existing/untouched if another phase installed them
```
