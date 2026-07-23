# Lab 18: Debugging xDS (Deliberate Misconfiguration)

## Objective

Deliberately introduce a broken `VirtualService` reference, then use the exact triage sequence from `../docs/10-configuration-analysis.md` to find and fix it — practicing the diagnostic workflow, not just reading about it.

## Concepts exercised

`istioctl analyze` → `proxy-status` → `proxy-config`, in that order (`../docs/10-configuration-analysis.md`, `../docs/14-troubleshooting.md`).

## Prerequisites

Labs 01, 03, 06 complete (subsets already defined via `destinationrule-frontend.yaml`).

## Steps

1. **Introduce the break**: create a copy of `demo/traffic/virtualservice-canary-90-10.yaml` (targets `frontend`) with the v2 subset name deliberately misspelled (e.g., `v2-typo` instead of `v2`):
   ```bash
   sed 's/subset: v2/subset: v2-typo/' demo/traffic/virtualservice-canary-90-10.yaml > /tmp/broken-vs.yaml
   kubectl apply -f /tmp/broken-vs.yaml
   ```

2. **Step 1 of the triage sequence — config consistency**:
   ```bash
   istioctl analyze -n istio-demo
   ```
   Expect `analyze` to flag the reference to a subset (`v2-typo`) that no `DestinationRule` defines — resolve the issue at the cheapest, earliest possible point, exactly as `../docs/10-configuration-analysis.md` describes.

3. **(For comparison) Step 2 — push state**:
   ```bash
   istioctl proxy-status
   ```
   Even though the real problem here is a config-consistency issue `analyze` already caught, check `proxy-status` anyway to build the habit — note whether affected proxies are `SYNCED` (they likely are; a bad subset reference doesn't necessarily prevent an ACK, since Envoy accepts a route pointing at a currently-nonexistent cluster and it just fails at request time).

4. **Step 3 — ground truth** (inspect `demo-client`'s own outbound route config, since it's the pod actually calling `frontend`):
   ```bash
   istioctl proxy-config routes demo-client -n istio-demo | grep -A3 v2-typo
   ```
   Confirm the broken subset reference is indeed present in the proxy's actual route config, not just the applied YAML.

5. **Fix it**:
   ```bash
   kubectl delete -f /tmp/broken-vs.yaml
   kubectl apply -f demo/traffic/virtualservice-canary-90-10.yaml
   ```

6. **Confirm `analyze` is clean again**:
   ```bash
   istioctl analyze -n istio-demo
   ```

## Validation

`istioctl analyze` transitions from flagging the issue to reporting no problems, and traffic to `frontend` behaves correctly again (re-run `./scripts/generate-traffic.sh http://frontend.istio-demo.svc.cluster.local 20` to confirm both subsets are reachable).

## Failure scenarios to notice

Try a *different* kind of break — delete the `DestinationRule` entirely while a `VirtualService` still references its subsets — and re-run the same triage sequence. Confirm `analyze` catches this variant too, and that it produces the same category of "subset not defined" finding even though the root cause (missing `DestinationRule` vs. typo'd subset name) is different.

## Cleanup

```bash
rm -f /tmp/broken-vs.yaml
```
Confirm `demo/traffic/virtualservice-canary-90-10.yaml`'s clean state is applied.

## Reflection

This lab's break was caught at step 1 (`analyze`) before ever needing steps 2 or 3. Construct (on paper, don't necessarily apply) a different kind of misconfiguration that `analyze` would **not** catch, but that `proxy-status` or `proxy-config` would reveal — what category of problem lives outside static config-consistency checking?
