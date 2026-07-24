# Lab 10: Distributed Tracing

## Objective

Find one full transaction's trace across all four services and read its waterfall like an incident responder would.

## Concepts exercised

`docs/04-distributed-tracing.md`'s full span tree, critical path, latency attribution.

## Prerequisites

Lab 09 complete.

## Steps

1. **Generate one clean request**:
   ```bash
   kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/
   ```

2. **Find the resulting trace**:
   ```bash
   make port-forward-jaeger &
   curl -s -G http://localhost:16686/api/traces --data-urlencode 'service=frontend' --data-urlencode 'limit=1' | python3 -m json.tool
   ```
   Or in the UI: service `frontend`, Find Traces, open the most recent.

3. **Identify every span** — you should see 7: `frontend` root SERVER span, `order.create` (custom), `order-service`'s CLIENT span to inventory, `inventory-service` SERVER span, `order-service`'s CLIENT span to payment, `payment-service` SERVER span, `payment.authorize` (custom).

4. **Find the critical path** — which span's *self* time (not counting children) is largest? In the Jaeger UI, this is usually visually obvious from the waterfall; confirm your read against the JSON's `duration` fields for each span directly.

5. **Check the dependency graph** now that you have real trace volume:
   ```bash
   curl -s "http://localhost:16686/api/dependencies?endTs=$(date +%s%3N)&lookback=3600000" | python3 -m json.tool
   ```
   Confirm it shows `frontend → order-service → {inventory-service, payment-service}` — matching the architecture exactly, derived entirely from trace data, not hand-configured anywhere.

## Validation

```bash
bash tests/traces-test.sh
```

## Failure scenarios to notice

Inject latency into `payment-service` (`make inject-latency ARGS="1500 apply"`), generate another request, and find its trace — confirm the `payment.authorize`/`payment.provider_call` spans are now visibly the dominant contributor to total trace duration in the waterfall, a direct, visual confirmation of latency attribution. Revert afterward (`make inject-latency ARGS="0 revert"`).

## Cleanup

```bash
make inject-latency ARGS="0 revert"
```

## Reflection

The dependency graph in step 5 was built entirely from trace data, with no separate architecture-diagram-maintenance step. What would happen to this graph's accuracy if a new service were added to the call chain but nobody updated any documentation — compare that to how `docs/DECISIONS.md`'s ADRs (hand-maintained) would behave in the same scenario.
