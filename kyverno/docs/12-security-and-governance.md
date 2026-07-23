# Security and Governance

## Kyverno vs. Pod Security Admission

Both operate at admission time; both can reject a Pod. They are not competitors so much as different altitudes:

| | Pod Security Admission | Kyverno |
| --- | --- | --- |
| Mechanism | Built into the API server, no extra component | A separate admission webhook process |
| Expressiveness | Three fixed profiles (`privileged`/`baseline`/`restricted`) | Arbitrary custom logic — any field, any resource kind, mutation, generation, image verification |
| Granularity | Namespace-wide label (`pod-security.kubernetes.io/enforce`) | Per-policy, per-rule, per-resource `match`/`exclude`, `PolicyException` |
| Performance | No network round-trip | Webhook round-trip (docs/01) |
| Failure mode | Cannot go "down" independently — it's part of the API server | Can be unavailable independently (docs/11 HA) |
| What it can express | Container-level Pod security fields only | Labels, resource limits, image provenance, cross-resource generation, anything JMESPath/CEL can reach |

**This repository's stance** (see `demo/namespace.yaml`'s own comment): `kyverno-demo` runs PSA at `privileged` (i.e., PSA imposes no restriction there) specifically so this lab's insecure-workloads examples can exist and be rejected *by Kyverno*, which is the thing being taught. In a real cluster, the two are typically layered: PSA's `restricted` or `baseline` profile as a fast, always-on floor across every namespace (cheap insurance against the most severe misconfigurations, no policy engine dependency), with Kyverno adding the organization-specific rules PSA structurally cannot express — required labels, resource limits, image provenance, generation, exceptions. Kyverno is not a replacement for PSA; PSA is not a replacement for Kyverno's expressiveness.

## Kyverno vs. OPA/Gatekeeper

Both are general-purpose Kubernetes admission policy engines. The practical difference for a platform team choosing between them: Gatekeeper policies are written in Rego (a genuinely separate language to learn, powerful but with its own learning curve distinct from Kubernetes YAML); Kyverno policies are Kubernetes-native YAML with JMESPath expressions (and, increasingly, CEL — docs/DECISIONS.md ADR-018), which is typically faster for a Kubernetes-fluent team to pick up and read without context-switching languages. Gatekeeper's constraint-template model separates "policy logic" (the Rego template) from "policy parameters" (the constraint instance) more explicitly than Kyverno's model does by default. Neither is strictly more powerful — the choice in practice usually comes down to team familiarity (Rego vs. YAML/JMESPath) and specific feature needs (Kyverno's native `generate`/`verifyImages`/`mutate` are more first-class than Gatekeeper's equivalents).

## Governance in practice

- **Policy ownership**: see docs/11-production-design.md.
- **Audit-first rollout**: root `docs/DECISIONS.md` ADR-013 — every enforce-mode policy in this lab has (or started as) an audit-mode twin.
- **Namespace exclusion discipline**: `config/namespaces.env`'s default exclusion list is deliberately short and documented (root `docs/DECISIONS.md` ADR-014) — `kube-system`/`kube-public`/`kube-node-lease` (Kubernetes' own system namespaces, where most policies genuinely don't apply meaningfully), `kyverno` (avoid Kyverno gating its own pods), `cilium`/`hubble` (the base platform's CNI, currently a no-op since Phase 2 installs both into `kube-system` — documented as such, not silently assumed). **Why broad exclusions weaken governance**: every namespace you exclude is a namespace where none of your policies apply at all, full stop — a single overly broad exclusion (e.g., excluding an entire `*-system` wildcard, or excluding by a label any team can self-apply) can silently create a policy-free zone that grows over time as more workloads land there, with no report, no warning, nothing — it simply never gets evaluated.
- **PolicyException scoping**: docs/09-policy-exceptions.md in full.

## Security boundaries

Kyverno's admission controller, by necessity, has broad read access across resource kinds (to evaluate policies against arbitrary objects) and write access to its own CRDs (reports, update requests). It does **not** need — and this lab's RBAC (as shipped by the official Helm chart) does not grant — write access to arbitrary application resources beyond what specific `mutate`/`generate`/`cleanup` rules actually require. Treat Kyverno's own ServiceAccount permissions as a security-relevant surface: a compromised Kyverno controller could, in principle, approve/mutate anything a policy author has configured it to touch, which is exactly why policy changes deserve the same review rigor as RBAC changes (see Governance above).
