# Performance and Scaling

## Admission latency

Every matching request pays the cost of: webhook network round-trip + policy evaluation time for every rule that matches. This is additive per policy, not parallelized across policies within one Kyverno controller call — a request matching 10 policies with 3 rules each evaluates up to 30 rules serially within that one AdmissionReview call, all inside the API server's `timeoutSeconds` budget (docs/01-kyverno-fundamentals.md).

## Number of policies and rules

There is no hard limit, but latency and background-scan load both scale roughly linearly with (policies × rules × matching resources). A cluster with hundreds of enforce-mode policies each with several rules is a meaningfully different operational profile than this lab's handful — watch webhook latency metrics (docs/10's "Metrics" section) as the real signal, not policy count in isolation, since a handful of expensive rules can cost more than dozens of cheap ones.

## Expensive API calls and complex JMESPath

`context.apiCall` (`policies/advanced/api-call-context-example.yaml`) adds a full API-server round-trip *inside* the admission-webhook call, before the rule's own evaluation even starts — this is the single most expensive thing a Kyverno rule can do, and it's paid on every matching admission request, not cached across requests by default. Complex `foreach`/nested JMESPath expressions (`policies/advanced/foreach-precondition-jmespath.yaml`) are CPU cost, not network cost, but still add up per-request. Prefer `context.configMap` (a simple read, no query logic) over `context.apiCall` wherever the data doesn't genuinely need to be a live query.

## Background scan load

Scales with (policies with `background: true`) × (matching resources) ÷ `resyncPeriod` — see docs/03-admission-and-background-processing.md. A large cluster with a short `resyncPeriod` and many background-enabled policies can generate meaningful sustained API server load from the background controller's own list/watch traffic, independent of admission-time cost entirely.

## Reports retention

`PolicyReport`/`ClusterPolicyReport` objects accumulate results — in a cluster with high churn (many short-lived resources) and many policies, report volume itself becomes a capacity concern (etcd storage, `kubectl get` response size). This lab's scale never approaches that threshold, but a production deployment should have an explicit retention/cleanup story for report data, the same way log retention is a deliberate decision, not an afterthought.

## Controller resource sizing

This lab's `install/values-minimum.yaml` and `values-recommended.yaml` are starting points sized for a 3-node local VirtualBox cluster, not production guidance — a production admission controller under real request volume needs load-tested `resources.requests/limits`, not values copied from a lab. Undersized CPU requests are a common, sneaky cause of admission latency spikes under load (CPU throttling, not an actual code-level slowdown).

## Webhook timeout tuning

`timeoutSeconds` (docs/01) is a hard ceiling on how long any single AdmissionReview call can take before the API server treats it as a failure, governed by `failurePolicy`. Raising it papers over slow policies rather than fixing them — the better fix, in order of preference: remove/optimize the expensive `context.apiCall` or `foreach` logic; split an expensive policy so only the genuinely-necessary rules run per resource kind (`match.any.resources.kinds` narrowing); only then, as a last resort, raise the timeout, and only with a clear understanding of what "the API server waits this long, worst case, on every matching request" actually costs you under load.

## Interview-level explanation

*"A team reports that `kubectl apply` feels slower since Kyverno enforce-mode policies went live — how do you investigate?"* — Start with Kyverno's own webhook latency metrics (per-policy, per-rule if available) rather than guessing; identify which specific policies/rules the slow requests actually match; look first for `context.apiCall` usage (the single most likely culprit) and complex `foreach` blocks; check whether `resources.requests` on the admission controller are actually being throttled under current load (CPU throttling looks like "policy is slow" but is actually "pod doesn't have enough CPU"); only after ruling those out, consider whether the policy count/rule count itself has genuinely outgrown current replica count and needs horizontal scaling (more admission-controller replicas, which parallelizes across *requests*, not within one request's rule evaluation).
