# Lab 01: Installing Istio (Sidecar Mode, Cilium CNI-Chained)

## Objective

Install Istio's control plane, CNI plugin, and ingress gateway in the correct order, understanding what each Helm release actually does.

## Concepts exercised

Install ordering (`../docs/02-istio-architecture.md`), CNI chaining with Cilium (`../docs/04-istio-cni-and-cilium.md`), resource profiles (`../config/lab-settings.env`'s `LAB_PROFILE`).

## Prerequisites

Lab 00 complete, including the Cilium CNI-chaining remediation command run manually if `verify-cluster` warned about it.

## Steps

1. **Choose a profile** (`minimum` or `recommended` — see `../install/istiod-values-{minimum,recommended}.yaml` for the difference: replica count, PodDisruptionBudget, anti-affinity):
   ```bash
   export LAB_PROFILE=recommended
   ```

2. **Install**:
   ```bash
   make install LAB_PROFILE=$LAB_PROFILE
   ```
   Watch the output — `scripts/install.sh` runs, in order: namespace creation → `base` chart (CRDs) → Gateway API CRDs (conditionally, tracked via `.generated/gateway-api-crds-owned.marker`) → **Cilium CNI-chaining hard-check** (fails here with the exact remediation if not ready) → `istiod` → `istio-cni` → `istio-ingress` gateway.

3. **Watch each component come up**:
   ```bash
   kubectl -n istio-system get pods -w
   ```
   Expect `istiod-*`, `istio-cni-node-*` (DaemonSet, one per node), and (in `istio-ingress`) the gateway Deployment.

4. **Confirm the installed revision**:
   ```bash
   istioctl version
   kubectl get pods -n istio-system -L istio.io/rev
   ```
   Confirm it matches `config/lab-settings.env`'s `ISTIO_REVISION` (`stable-1-30`) — see `../docs/13-upgrades-and-disaster-recovery.md` for why this lab uses a named revision.

## Validation

```bash
make validate-installation
```
Runs `scripts/validate-installation.sh` — Helm release presence, CNI DaemonSet health, ingress gateway readiness. Compare against `../tests/expected-results.md`'s `installation-test.sh` section.

## Failure scenarios to notice

If step 2 hard-fails at the Cilium chaining check, this is **expected and correct** if you skipped the Lab 00 remediation — re-run the printed `helm upgrade` command against Cilium, then re-run `make install`.

## Cleanup

Leave the install in place — subsequent labs build on it. To fully remove it later: `make uninstall` (see `lab-20-production-readiness.md` for the full teardown discussion).

## Reflection

Why does `istio-cni` install *after* `istiod` but *before* the ingress gateway in this lab's ordering? What would go wrong if CNI were installed first, before `istiod` exists to serve it xDS config?
