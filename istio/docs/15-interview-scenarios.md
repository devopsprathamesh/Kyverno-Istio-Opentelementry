# Interview Scenarios

This document consolidates the "Interview-level explanation" sections from `01`–`14` into scenario-driven practice, plus additional cross-cutting questions those individual documents don't fully cover alone. Treat each as a prompt to answer out loud before checking the reference doc.

## Architecture and internals

1. Where did Pilot/Citadel/Galley go, and what replaced them? → `02-istio-architecture.md`
2. Explain, mechanically, how traffic gets from an application into its sidecar without any code change. → `03-envoy-and-sidecar-internals.md`
3. What's the difference between the Istio CNI plugin's interception model and the older init-container model, and which does this lab use? → `03-envoy-and-sidecar-internals.md`
4. What is xDS, and name the specific discovery services and what each delivers. → `01-service-mesh-fundamentals.md`
5. Why is config propagation "eventually consistent," and what tool proves whether a specific proxy has caught up? → `01-service-mesh-fundamentals.md`, `10-configuration-analysis.md`

## Cilium and CNI integration

6. You have Cilium as your cluster's CNI. How do you add Istio's sidecar data plane without replacing it? → `04-istio-cni-and-cilium.md`
7. What two Cilium Helm values does CNI chaining require, and what does each actually do? → `04-istio-cni-and-cilium.md`
8. Why does `scripts/install.sh` hard-fail before installing Istio CNI if Cilium isn't chaining-ready, rather than warning and continuing? → `04-istio-cni-and-cilium.md`

## Traffic management

9. What's the difference between `VirtualService` and `DestinationRule`, concretely, and why does a canary release need both? → `05-traffic-management.md`
10. What does a `Sidecar` resource actually restrict, and why does that matter at scale? → `05-traffic-management.md`, `11-production-design.md`
11. Why is a small-sample canary-split test expected to deviate from the configured weight, and how does this lab's test account for that? → `05-traffic-management.md`

## Security

12. Walk through how Istio authenticates and authorizes a service-to-service call, layer by layer. → `06-service-security-and-mtls.md`
13. Does `RequestAuthentication` alone reject an unauthenticated request? Why or why not? → `06-service-security-and-mtls.md`
14. Why is SPIFFE-identity-based authorization not spoofable by a misbehaving application, unlike IP-based rules? → `06-service-security-and-mtls.md`

## Ingress/egress

15. How does external traffic reach a pod in the mesh, hop by hop? → `07-gateways-and-ingress.md`
16. Why does this lab use `ClusterIP` + port-forward instead of `LoadBalancer` for its ingress gateway? → `07-gateways-and-ingress.md`
17. Is Istio's default egress posture allow or deny? What actually changes that, concretely? → `08-egress-and-serviceentry.md`
18. What's the difference between a `ServiceEntry` and a `Sidecar` resource's egress scoping, and why do you often need both together? → `08-egress-and-serviceentry.md`

## Resilience

19. Where do retries/timeouts live vs. where circuit breaking lives, and why does that split make sense? → `09-resilience-patterns.md`
20. Explain the difference between connection-pool limits and outlier detection — both are called "circuit breaking" colloquially, but they do different things. → `09-resilience-patterns.md`
21. Why might a circuit-breaker test show no overflow rejections even with a correctly configured connection-pool limit? → `09-resilience-patterns.md`

## Debugging

22. A `VirtualService` change doesn't seem to take effect. What's your triage order, and why that order specifically? → `10-configuration-analysis.md`, `14-troubleshooting.md`
23. What's the difference between `istioctl validate` and `istioctl analyze`? → `10-configuration-analysis.md`
24. Why is `istioctl proxy-config`, not the applied YAML, the actual ground truth for what a proxy will do? → `10-configuration-analysis.md`, `03-envoy-and-sidecar-internals.md`

## Production and operations

25. What would you change about a lab-grade Istio setup before calling it production-ready? Name at least four concrete gaps. → `11-production-design.md`
26. Where does the per-request performance cost of a service mesh actually come from, mechanically? → `12-performance-and-capacity.md`
27. Why does named-revision installation matter for future upgrades, even if you only ever install one revision today? → `13-upgrades-and-disaster-recovery.md`
28. What's this lab's actual disaster-recovery story, and why is it simpler than a stateful system's? → `13-upgrades-and-disaster-recovery.md`
29. Explain a canary control-plane upgrade end to end — what gets installed, what gets relabeled, what gets rolled. → `13-upgrades-and-disaster-recovery.md`

## Ambient mode and future direction

30. What is ambient mode, at a high level, and how does its interception model differ from sidecar mode? → `16-future-ambient-mode.md`
31. Why does this lab not implement ambient mode, and what would have to change to adopt it later? → `16-future-ambient-mode.md`

## Cross-cutting / synthesis questions

32. Trace one request from an external client through the ingress gateway, two east-west hops, and back — name every policy resource that could affect it at each hop.
33. A workload's sidecar was just injected, but calls to it are being rejected. List every layer that could be responsible, in the order you'd check them.
34. Compare Istio's `AuthorizationPolicy` model to Kyverno's admission-time policy enforcement (`../../kyverno/docs/`) — what's fundamentally different about *when* and *what* each enforces?
35. If you had to add one more production hardening step beyond what this lab implements, which would you prioritize, and why?
36. Explain why this lab retains kube-proxy alongside Cilium and Istio, rather than removing it — what would break, and for whom? → root `docs/DECISIONS.md` ADR-003
37. A `Sidecar` resource, a `PeerAuthentication`, and an `AuthorizationPolicy` all exist in the same namespace. Explain what each one is actually responsible for, without overlap.
38. Why is "the mesh adds network latency" an imprecise claim, and what's the more accurate framing? → `12-performance-and-capacity.md`
39. What's the single biggest operational risk this lab's design explicitly calls out and defers to a later phase (rather than solving now)?
40. If `istioctl analyze` is clean and `istioctl proxy-status` shows `SYNCED` everywhere, but traffic still isn't behaving as expected, where do you look next, and why?

## Interview-level explanation

*"How would you prepare someone to actually defend these answers, not just recite them?"* — Every answer above should be traceable to a specific manifest, script, or test in this lab, not just a definition memorized from documentation — the labs in `../labs/` are what turn each of these from a rehearsed answer into something demonstrated: running the exact failure, observing the exact remediation, reading the exact `istioctl` output referenced. An answer backed by "I ran this and here's what I saw" is categorically stronger than one backed only by "I read that this is how it works."
