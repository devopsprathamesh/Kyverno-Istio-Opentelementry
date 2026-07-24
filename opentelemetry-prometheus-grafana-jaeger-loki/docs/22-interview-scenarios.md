# Interview Scenarios

50+ senior-level scenario-based questions, each cross-referenced to the doc/lab that answers it in full depth. For the incident-style scenarios, answers follow the structure: **Investigation → Root cause → Immediate mitigation → Permanent fix → Validation → Prevention** — practice stating all six explicitly, not just the root cause.

## Collector architecture

1. What's the difference between a receiver, processor, exporter, and connector? → `09-collector-internals.md`
2. Why does `memory_limiter` run first in every pipeline, always? → `09-collector-internals.md`
3. What's the difference between `sending_queue` and `retry_on_failure`, and how do they interact? → `09-collector-internals.md`, `tests/resilience-test.sh`
4. Why is `queue_size` measured in batches, not individual items, and why does that matter for sizing? → `09-collector-internals.md`, `18-performance-and-capacity.md`

## Agent vs. gateway

5. Why split Collector deployment into an Agent DaemonSet and a Gateway Deployment? → `10-collector-deployment-patterns.md`
6. What would break if you ran only a Gateway, no Agent? → `06-logs.md` (filelog needs node-local access)
7. What would break if you ran only an Agent, no Gateway? → `09-collector-internals.md` (no central tail sampling)
8. Why does `scripts/install-collector.sh` install the Gateway before the Agent? → `10-collector-deployment-patterns.md`

## Filelog

9. Why is `filelog` a contrib-only, not core, receiver? → `docs/VERSIONS.md` Phase 5 addendum
10. What's the CRI log format, and what does the `container` operator do with it? → `06-logs.md`
11. Explain `start_at: beginning` and its duplication/loss tradeoffs. → `06-logs.md`
12. Why does this lab's Agent run as non-root, and what real risk does that create? → `17-security-and-governance.md`, `21-troubleshooting.md` "Filelog permission denied"
13. How does the `file_storage` checkpoint extension prevent re-reading logs after a restart? → `06-logs.md`

## OTLP

14. What's the difference between OTLP gRPC and OTLP HTTP, practically? → `02-opentelemetry-fundamentals.md`
15. What ports does each use in this lab, and what happens if you mismatch them? → `02-opentelemetry-fundamentals.md`, `21-troubleshooting.md`

## Context propagation

16. What's in a `traceparent` header, byte for byte? → `07-context-propagation.md`
17. What's the difference between trace context and baggage? → `07-context-propagation.md`
18. What causes a "partial trace" — some spans present, others missing? → `21-troubleshooting.md`

## Partial traces / sampling

19. Explain head sampling vs. tail sampling, and when you'd choose each. → `09-collector-internals.md`
20. Why can only tail sampling guarantee "always keep error traces"? → `09-collector-internals.md`
21. What's the memory cost of tail sampling, and why does it grow with `num_traces`? → `09-collector-internals.md`, `18-performance-and-capacity.md`
22. Why is consistent trace-ID routing needed for tail sampling at multi-Gateway-replica scale? → `10-collector-deployment-patterns.md`, `16-production-design.md`

## Prometheus

23. Why pull instead of push for metrics? → `11-prometheus-architecture.md`
24. What's the difference between `ServiceMonitor` and `PodMonitor`, and why does this lab need both? → `11-prometheus-architecture.md`
25. Why does this lab use scrape-based Collector integration instead of remote write? → `11-prometheus-architecture.md`, `docs/DECISIONS.md` ADR-028
26. What does the WAL protect against? → `11-prometheus-architecture.md`

## PromQL

27. Why does `histogram_quantile()` need bucket data, not raw samples? → `05-metrics.md`
28. What's the difference between `rate()` and `increase()`, and when would a counter reset break one but not the other? → `prometheus/queries/promql-examples.md`

## Metrics cardinality

29. Why is `order.id` a catastrophic metric label choice? → `05-metrics.md`, `18-performance-and-capacity.md`
30. How would you detect a cardinality explosion before it becomes a cost incident? → `19-cost-optimization.md`

## Exemplars

31. What is an exemplar, concretely, and what two things are required for it to work? → `08-telemetry-correlation.md`
32. Why might exemplar dots simply not appear on a Grafana panel? → `21-troubleshooting.md`

## Jaeger

33. Why is Jaeger's Operator deprecated, and what replaced it? → `13-jaeger-architecture.md`, `docs/DECISIONS.md` ADR-027
34. Why is Jaeger's all-in-one mode explicitly not production-grade? → `13-jaeger-architecture.md`
35. How does the service dependency graph get built, mechanically? → `04-distributed-tracing.md`

## Loki

36. Why does Loki index only labels, not full log content? → `14-loki-architecture.md`
37. What's the current correct deployment-mode name, and why is `SimpleScalable` the wrong answer now? → `14-loki-architecture.md`, `docs/VERSIONS.md`
38. Why was the Collector Contrib `loki` exporter removed, and what replaced it? → `06-logs.md`, `docs/DECISIONS.md`

## Log cardinality

39. Why is `trace_id` carried as Loki structured metadata instead of a label? → `06-logs.md`, `loki/logql/logql-examples.md`

## Grafana

40. In one sentence: what does Grafana NOT do that a newcomer often assumes it does? → `12-grafana-architecture.md`
41. What's the difference between `tracesToLogsV2` and `derivedFields`, direction-wise? → `08-telemetry-correlation.md`

## Correlation

42. How would you PROVE trace-log correlation works, not just that it's configured? → `08-telemetry-correlation.md`, `tests/correlation-test.sh`

## Queues, backpressure, data loss

43. Walk through exactly what happens when a backend goes down, step by step, in this lab's pipeline. → `09-collector-internals.md`, `tests/resilience-test.sh`
44. What's this lab's one real, unaddressed data-loss gap around Gateway restarts during an outage? → `16-production-design.md`

## Scaling

45. What's the actual bottleneck that limits Gateway horizontal scaling for tail-sampled traces? → `10-collector-deployment-patterns.md`, `16-production-design.md`

## Security

46. What OTLP authentication options exist for production, and which does this lab use? → `17-security-and-governance.md`
47. Where is sensitive data actually stripped in this pipeline, and why there specifically? → `17-security-and-governance.md`, `06-logs.md`

## Multi-tenancy

48. What does "single-tenant Loki" actually mean operationally, and what would multi-tenant require? → `17-security-and-governance.md`

## HA / DR

49. Which components in this lab's "recommended" profile are actually HA, and which just look bigger? → `20-high-availability-and-dr.md`
50. What's recoverable from Git alone vs. what needs an external backup? → `16-production-design.md`

## Cost

51. If a storage bill spiked overnight, what would you check first, and why? → `19-cost-optimization.md`

## Kubernetes metadata

52. How does telemetry get tagged with `k8s.namespace.name` automatically, mechanically? → `15-kubernetes-observability.md`

## Operator / auto-instrumentation

53. Walk through exactly what the Operator's webhook injects into a pod, for Node.js specifically. → `03-opentelemetry-architecture.md`, `operator/examples/README.md`
54. Why does `inventory-service`'s `requirements.txt` have zero `opentelemetry-*` packages? → `demo-application/inventory-service/requirements.txt`, `docs/DECISIONS.md` ADR-031

## Production incidents (full six-part answer expected)

55. **Scenario**: P95 latency alert fires for `payment-service`. Walk the full investigation. → Start: `job:http_request_duration:p95_5m` confirms which service/window. Check Grafana's `service-performance` dashboard, click through an exemplar to the actual slow trace in Jaeger, read the waterfall for where time went. If it's `payment.provider_call`, that's the (simulated) external dependency — check `LATENCY_MS`. Mitigation: none needed if this is an intentional lab exercise (`scripts/inject-latency.sh`); in a real incident, investigate the actual downstream dependency. Fix: address the real slow dependency or add a stricter timeout. Validate: re-check the P95 recording rule after mitigation. Prevent: this exact loop (metric → exemplar → trace → root cause) is the incident workflow `combined-observability-lab/scenarios/` walks end to end.
56. **Scenario**: Traces show up for `frontend` but never for `payment-service`. → Investigation: is `payment-service` even being called (check `order-service`'s logs/traces first)? Root cause candidates: SDK not exporting (`21-troubleshooting.md`), Collector unreachable from that pod specifically (NetworkPolicy?), or tail sampling dropping all of them (unlikely unless volume is very low and none are errors/slow). Six-part structure per `21-troubleshooting.md`'s tracing table.
57. **Scenario**: Loki shows logs, but none have `trace_id`. → Root cause: `transform/log_trace_context` isn't finding `attributes.trace_id`, meaning the app's own JSON body never had a `trace_id` field, meaning the app's log formatter isn't reading the active span — check `demo-application/*/app.py`'s formatter code directly. Full structure: `21-troubleshooting.md` "Trace ID missing from logs."

## Interview-level explanation

*"How would you prepare to actually defend these answers under follow-up questions, not just recite them?"* — Every answer above traces back to a real file in this lab, not a memorized definition — `docs/09-collector-internals.md`'s queue/retry explanation matches `collector/gateway/configmap.yaml`'s actual `sending_queue`/`retry_on_failure` values; `tests/resilience-test.sh` is a runnable demonstration of question 43's answer, not just a claim about it. An answer backed by "here's the exact config, here's the test that proves it" survives follow-up questions in a way a purely definitional answer doesn't — that's the entire design principle behind pairing every doc in this directory with real, runnable artifacts elsewhere in the module.
