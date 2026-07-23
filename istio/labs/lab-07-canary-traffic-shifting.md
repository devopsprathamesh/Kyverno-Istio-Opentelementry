# Lab 07: Canary Traffic Shifting

## Objective

Progress `frontend` through a 3-stage canary rollout — 90/10, 50/50, full cutover — observing the split statistically across each stage.

## Concepts exercised

`VirtualService` weighted routing on top of Lab 06's subsets (`../docs/05-traffic-management.md`).

## Prerequisites

Labs 01, 03, 06 complete (subsets already defined).

## Steps

1. **Stage 1 — 90/10**:
   ```bash
   kubectl apply -f demo/traffic/virtualservice-canary-90-10.yaml
   ./scripts/generate-traffic.sh http://frontend.istio-demo.svc.cluster.local 100 10
   ```
   Expect roughly 90 v1 / 10 v2 in the printed response-code/hostname summary, within `config/lab-settings.env`'s `TRAFFIC_STATISTICAL_TOLERANCE_PERCENT`.

2. **Stage 2 — 50/50**:
   ```bash
   kubectl apply -f demo/traffic/virtualservice-canary-50-50.yaml
   ./scripts/generate-traffic.sh http://frontend.istio-demo.svc.cluster.local 100 10
   ```

3. **Stage 3 — full cutover**:
   ```bash
   kubectl apply -f demo/traffic/virtualservice-canary-0-100.yaml
   ./scripts/generate-traffic.sh http://frontend.istio-demo.svc.cluster.local 100 10
   ```
   Expect ~100% v2.

## Validation

```bash
../tests/traffic-routing-test.sh
```
Matches `../tests/expected-results.md`: `[PASS] Canary distribution within statistical tolerance.`

## Failure scenarios to notice

Repeat stage 1 with a tiny sample:
```bash
./scripts/generate-traffic.sh http://frontend.istio-demo.svc.cluster.local 5 5
```
Observe how far a 5-request sample can land from 90/10 — concrete evidence behind `../docs/05-traffic-management.md`'s warning against expecting exact ratios on small samples. Weighted routing is a per-request probabilistic decision made inside Envoy's RDS-pushed route config — there's no external load balancer or extra hop involved.

## Cleanup

Leave the final `VirtualService` state applied (stage 3, 0/100 v2), or reapply `virtualservice-canary-90-10.yaml` if you want a clean starting point for other labs.

## Reflection

Why is the weighted decision made entirely inside the calling sidecar's own Envoy rather than by a centralized router? What would change about latency and failure isolation if the split were instead decided by a separate, shared load-balancing service?
