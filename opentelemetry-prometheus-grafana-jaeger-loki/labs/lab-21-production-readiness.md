# Lab 21: Production Readiness

## Objective

Run this module's full validation suite end to end, collect a debug bundle, review `docs/16-production-design.md`'s gap list against what's actually installed, and perform a clean, scoped teardown.

## Concepts exercised

Synthesizes the whole module — this is the capstone lab, mirroring `../../istio/labs/lab-20-production-readiness.md`'s equivalent role in that module.

## Prerequisites

As many prior labs as you've completed — this is a capstone, not a new concept.

## Steps

1. **Full status snapshot**:
   ```bash
   make status
   ```

2. **Full runtime validation**:
   ```bash
   make test-runtime
   ```
   Review against `tests/expected-results.md` line by line.

3. **Collect a debug bundle**:
   ```bash
   make debug-bundle
   ```
   Inspect `.generated/debug-bundles/` — confirm no Secret contents, passwords, tokens, or full kubeconfig are present (`scripts/collect-debug-bundle.sh`'s own redaction/exclusion — verify it actually held).

4. **Work through `docs/16-production-design.md`'s comparison tables** against what's actually running:
   ```bash
   kubectl -n observability get pods -o wide
   kubectl -n observability get deployment kube-prometheus-stack-alertmanager -o jsonpath='{.spec.replicas}'
   kubectl -n opentelemetry get deployment otel-collector-gateway -o jsonpath='{.spec.replicas}'
   ```
   For each row in the production-design tables, state explicitly: implemented-here-at-lab-scale, or deferred-and-documented, and why.

5. **Scoped cleanup — demo and lab-applied config only**:
   ```bash
   make clean
   ```
   Confirm backends remain untouched:
   ```bash
   kubectl -n observability get pods
   ```

6. **(Optional — only if you intend to fully remove this module) Full uninstall**:
   ```bash
   make uninstall-all
   ```
   Read the printed `[WARN]` output first. Confirm afterward:
   ```bash
   kubectl get namespace observability opentelemetry otel-demo 2>&1
   helm list -A | grep -E 'prometheus|grafana|jaeger|loki|operator'
   ```
   Confirm Cilium, kube-proxy, and every other module remain completely untouched:
   ```bash
   kubectl get daemonset -n kube-system cilium kube-proxy
   ```

## Validation

`make test-runtime` passes (or shows only documented, non-fatal `[WARN]`s per `tests/expected-results.md`); the debug bundle is sanitized; `make clean` leaves backend namespaces untouched; if you ran `make uninstall-all`, Cilium/kube-proxy/other modules are confirmed completely unaffected afterward.

## Failure scenarios to notice

Run `make uninstall-all` without reading the printed warning, then reason through exactly what you'd need to run to get back to a fully-working state (`make install-all` again is idempotent and values-file-driven — nothing about this module's design depends on manually-reconstructed state, per `docs/16-production-design.md`'s disaster-recovery section).

## Cleanup

This lab's steps 5–6 **are** the cleanup — no further action needed.

## Reflection

Walk through `docs/16-production-design.md`'s full comparison table one more time and, for each row, state in one sentence what you specifically observed in this lab series that demonstrates you understand *why* it's a gap, not just that it's listed as one — the same closing exercise `docs/22-interview-scenarios.md` frames as the real test of whether you can defend these answers under follow-up questions.
