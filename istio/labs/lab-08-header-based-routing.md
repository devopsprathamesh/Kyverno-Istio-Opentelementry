# Lab 08: Header-Based Routing

## Objective

Route requests to a specific version based on a request header (`x-canary-user: true`) — the pattern used for internal-tester or beta-cohort routing, independent of overall traffic weight, and deterministic rather than probabilistic.

## Concepts exercised

`VirtualService` header `match` conditions evaluated before/instead of weighted routing (`../docs/05-traffic-management.md`).

## Prerequisites

Labs 01, 03, 06 complete (subsets already defined).

## Steps

1. **Apply header-based routing**:
   ```bash
   kubectl apply -f demo/traffic/virtualservice-header-routing.yaml
   ```
   Inspect the file — requests carrying `x-canary-user: true` route to `v2`; every other request falls back to `v1`. Route order matters here too (first match wins) — see `../docs/05-traffic-management.md`.

2. **Call without the header** (recreate `demo-client` from Lab 03 if needed):
   ```bash
   for i in $(seq 1 5); do kubectl exec -n istio-demo demo-client -- curl -s http://frontend/ | grep -i hostname; done
   ```
   Expect only v1 hostnames.

3. **Call with the header**:
   ```bash
   for i in $(seq 1 5); do kubectl exec -n istio-demo demo-client -- curl -s -H "x-canary-user: true" http://frontend/ | grep -i hostname; done
   ```
   Expect only v2 hostnames, deterministically — unlike Lab 07's weighted split, the same header should get the same subset every time, not probabilistically.

## Validation

Header-present requests land on v2 100% of the time across at least 10 repeated calls; header-absent requests land on v1 100% of the time.

## Failure scenarios to notice

Send the header with a near-miss value (`x-canary-user: yes` instead of `true`) and observe it silently falls through to the default (v1) route rather than erroring — header match conditions are exact-match by default; a typo doesn't fail loudly, it just doesn't match.

## Cleanup

Reapply `demo/traffic/virtualservice-canary-90-10.yaml` (Lab 07) if you want to reset `frontend` routing before later labs, since this lab's `VirtualService` replaces Lab 07's.

## Reflection

Why is header-based routing deterministic while weighted routing (Lab 07) is probabilistic — what's structurally different in how Envoy evaluates a `match` condition versus a `weight` field? Which would you use for a canary rollout to real users, and which for routing your own internal QA traffic to a specific version, and why?
