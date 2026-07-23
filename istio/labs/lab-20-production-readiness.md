# Lab 20: Production Readiness Review and Teardown

## Objective

Run this lab's own validation suite end-to-end, produce a debug bundle, review the gap list between this lab and a real production mesh (`../docs/11-production-design.md`), and perform a clean, scoped teardown.

## Concepts exercised

Synthesizes the whole module: `../docs/11-production-design.md`'s explicit not-implemented-here list, `../docs/10-configuration-analysis.md`'s tooling, this module's clean/uninstall boundary (never touching Cilium/kube-proxy/the cluster).

## Prerequisites

As many prior labs as you've completed — this lab is a capstone, not a new concept.

## Steps

1. **Full status snapshot**:
   ```bash
   make status
   ```

2. **Full runtime validation** (every test script this module ships):
   ```bash
   make test-runtime
   ```
   Review the output against `../tests/expected-results.md` line by line — note any `[WARN]`s and whether they're the documented, non-fatal kind (e.g., circuit-breaking's possible no-overflow warning) or something new.

3. **Collect a debug bundle**:
   ```bash
   make debug-bundle
   ```
   Inspect `.generated/debug-bundles/` — confirm it contains `istioctl analyze` output, `proxy-status`, relevant pod descriptions/events, without any certificate private-key material or other secrets (`scripts/collect-debug-bundle.sh` is expected to sanitize this — verify it actually did).

4. **Work through the production-readiness gap list** (`../docs/11-production-design.md`'s table) against what's actually installed on this cluster right now:
   ```bash
   helm get values istiod -n istio-system | grep -i replicaCount
   kubectl get authorizationpolicy,peerauthentication -n istio-demo
   kubectl get sidecar -n istio-demo
   ```
   For each row in that table, state explicitly: implemented-here-at-lab-scale, or deferred-and-documented, and why.

5. **Scoped cleanup — demo and lab-applied config only**:
   ```bash
   make clean
   ```
   Runs `scripts/clean.sh all` — removes `istio-demo`/`istio-external` and any temporary lab namespaces, and lab-applied config objects. Confirm Istio's own control plane is untouched:
   ```bash
   kubectl get pods -n istio-system
   kubectl get pods -n istio-ingress
   ```

6. **(Optional — only if you intend to fully remove Istio from this cluster) Full uninstall**:
   ```bash
   make uninstall
   ```
   Read the printed `[WARN]` output first — by default this keeps CRDs (`REMOVE_CRDS=true` would delete every `VirtualService`/`DestinationRule`/etc. cluster-wide, not just this lab's own, and Gateway API CRDs are only removed if this lab's own install tracked owning them). Confirm afterward:
   ```bash
   kubectl get namespace istio-system istio-ingress 2>&1
   helm list -n istio-system
   ```
   Confirm Cilium, kube-proxy, and CoreDNS remain completely untouched:
   ```bash
   kubectl get daemonset -n kube-system cilium
   kubectl get daemonset -n kube-system kube-proxy
   ```

## Validation

`make test-runtime` passes (or shows only documented, non-fatal `[WARN]`s); the debug bundle is sanitized; `make clean` leaves `istio-system`/`istio-ingress` untouched; if you ran `make uninstall`, Cilium/kube-proxy/CoreDNS are confirmed completely unaffected afterward.

## Failure scenarios to notice

Run `make uninstall` without first reading its printed warning, and reason afterward about exactly what you'd need to run to get back to Lab 01's starting state (hint: `make install` again is idempotent and values-file-driven — nothing about this module's design depends on manually-reconstructed state, per `../docs/13-upgrades-and-disaster-recovery.md`'s disaster-recovery discussion).

## Cleanup

This lab's steps 5–6 **are** the cleanup — no further action needed.

## Reflection

Walk through `../docs/11-production-design.md`'s full gap table one more time and, for each row, state in one sentence what you specifically observed in this lab series that demonstrates you understand *why* it's a gap, not just that it's listed as one. This is the exercise `../docs/15-interview-scenarios.md`'s closing note describes — an answer backed by "I ran this and saw X" rather than only "I read that this is how it works."
