# Lab 15: Sampling

## Objective

Demonstrate every sampling mode this lab touches: SDK-level `parentbased_traceidratio`, and Gateway-level tail sampling's three policies (keep-all-errors, keep-slow-traces, probabilistic-baseline) — directly, with counted evidence, not just configuration review.

## Concepts exercised

`docs/09-collector-internals.md`'s head-vs-tail sampling.

## Prerequisites

Labs 08/09, 10 complete.

## Steps

1. **Confirm the SDK sampler configuration**:
   ```bash
   grep -A2 sampler operator/instrumentation/*.yaml
   ```
   Note `parentbased_traceidratio`, argument `1.0` — this lab's SDKs always create real spans (ratio 1.0), deferring all actual sampling decisions to the Gateway's tail_sampling processor. (Setting this lower, e.g. `0.5`, would demonstrate genuine head/probabilistic sampling at the SDK level — try it as an optional variation: edit a copy, reapply, restart the affected Deployment, and observe roughly half as many root spans created.)

2. **Prove "keep-all-errors" works** — force 100% payment failures, send exactly 10 requests, count error traces found:
   ```bash
   make inject-errors ARGS="100 apply"
   for i in $(seq 1 10); do kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/; done
   make inject-errors ARGS="0 revert"
   sleep 25   # tail_sampling.decision_wait (10s) + export/index delay
   make port-forward-jaeger &
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=payment-service' --data-urlencode 'tags={"error":"true"}' --data-urlencode 'limit=10' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'
   ```
   Expect close to 10 (ideally exactly 10).

3. **Prove "keep-slow-traces" works** — inject latency above the 500ms threshold (`config/lab-settings.env` `TAIL_SAMPLING_SLOW_TRACE_THRESHOLD_MS`):
   ```bash
   make inject-latency ARGS="800 apply"
   for i in $(seq 1 10); do kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/; done
   make inject-latency ARGS="0 revert"
   sleep 25
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=payment-service' --data-urlencode 'minDuration=500ms' --data-urlencode 'limit=10' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'
   ```
   Expect close to 10.

4. **Observe the probabilistic-baseline policy** — send 50 NORMAL (fast, successful) requests and count how many traces survive:
   ```bash
   make generate-load ARGS="50 5 30"
   sleep 25
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=frontend' --data-urlencode 'limit=100' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))'
   ```
   Expect roughly 15% of 50 (≈7-8), within `config/lab-settings.env`'s `STATISTICAL_TOLERANCE_PERCENT`.

## Validation

```bash
bash tests/sampling-test.sh
```

## Failure scenarios to notice

Repeat step 4 with only 5 requests instead of 50 — observe how far the result can land from the "expected" 15% (0 or 1 out of 5 is entirely plausible) — the same small-sample-size lesson `../../istio/docs/05-traffic-management.md` teaches for canary routing, here applied to sampling instead.

## Cleanup

```bash
make inject-errors ARGS="0 revert"
make inject-latency ARGS="0 revert"
```

## Reflection

Steps 2 and 3 both used deliberately extreme values (100% failure, 800ms latency) rather than realistic ones. Why does that make for a *better* test of the tail-sampling policy specifically, compared to using more realistic, moderate values?
