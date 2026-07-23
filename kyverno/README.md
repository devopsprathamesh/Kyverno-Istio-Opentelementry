# kyverno

Independent, production-oriented Kyverno hands-on lab: policy engine fundamentals, all major policy types, controlled failure scenarios, and automated validation/cleanup — installable and removable without touching Istio or the observability stack.

## What Kyverno is

A Kubernetes-native policy engine that runs as an admission webhook (validating and mutating) plus background/cleanup/reports controllers, letting you express "this class of resource must/must not look like X" as version-controlled Kubernetes YAML rather than code review convention. See [`docs/01-kyverno-fundamentals.md`](docs/01-kyverno-fundamentals.md).

## Why it is used

Admission control is the only point in Kubernetes' request lifecycle where you can reliably intercept *every* path a resource enters the cluster — CI pipelines, `kubectl` from a laptop, a controller's reconcile loop — and Kyverno turns organizational policy into something the API server itself enforces or reports on, consistently.

## Architecture

Four independent controllers (admission, background, cleanup, reports), CRDs, webhook configs, RBAC, leader election — see [`docs/02-architecture-and-internals.md`](docs/02-architecture-and-internals.md).

## How it differs from Pod Security Admission

PSA is built into the API server, free, fast, but limited to three fixed profiles. Kyverno is a separate component with a real availability dependency, but arbitrarily expressive. This lab runs both, layered — see [`docs/12-security-and-governance.md`](docs/12-security-and-governance.md) "Kyverno vs. Pod Security Admission".

## How it differs from OPA/Gatekeeper

Both are general admission policy engines; the practical difference is Rego (Gatekeeper) vs. Kubernetes-native YAML/JMESPath (Kyverno) — see [`docs/12-security-and-governance.md`](docs/12-security-and-governance.md) "Kyverno vs. OPA/Gatekeeper".

## Prerequisites

`kubectl`, `helm`, the Kyverno CLI (optional but recommended for offline testing), and a reachable cluster. Run `make prerequisites` — see [`labs/lab-00-prerequisites.md`](labs/lab-00-prerequisites.md).

## Base cluster dependency

This module **never** provisions or destroys Kubernetes itself, and never invokes Vagrant. It depends entirely on [`../auto-setup-default-kube-env/`](../auto-setup-default-kube-env/) already being up. Every install/runtime target in this module's Makefile runs `verify-cluster` first, which confirms the reachable cluster is genuinely the intended local learning cluster (API endpoint `192.168.56.10`, nodes `otel-control-plane`/`otel-worker-1`/`otel-worker-2`) — not just "a cluster exists" — and refuses to proceed with a clear mismatch report otherwise.

## Version matrix

| Component | Version | Source |
| --- | --- | --- |
| Kyverno Helm chart | 3.8.2 | `kyverno.github.io/kyverno/index.yaml` |
| Kyverno application | v1.18.2 | Same index; supports Kubernetes v1.33–v1.35 |
| Kyverno CLI | v1.18.2 | Same repo/release as the application |
| Policy Reporter (optional) | chart 3.8.1 / app 3.8.1 | `kyverno.github.io/policy-reporter/index.yaml` |

Full detail, sources, and the base-platform Kubernetes compatibility note: root [`../docs/VERSIONS.md`](../docs/VERSIONS.md) "Phase 3 addendum". Centralized in [`config/versions.env`](config/versions.env).

## Quick start

The quick-start path checks the cluster before assuming it exists — do not skip `verify-cluster`:

```bash
cd ~/github/Kyverno-Istio-Opentelementry/auto-setup-default-kube-env
make setup LAB_PROFILE=recommended
make validate

export KUBECONFIG="$(pwd)/.generated/kubeconfig"

cd ../kyverno
make prerequisites
make verify-cluster
make install LAB_PROFILE=recommended
make validate-installation
make deploy-demo
make test
```

## Installation

`make install LAB_PROFILE=minimum|recommended` — official Helm chart, pinned version, `install/values-minimum.yaml`/`values-recommended.yaml`. See [`labs/lab-01-install-kyverno.md`](labs/lab-01-install-kyverno.md) and [`docs/11-production-design.md`](docs/11-production-design.md) for what each profile actually configures (replica counts, PodDisruptionBudget, anti-affinity).

## Validation

`make validate-installation` — CRDs, controllers, webhooks, RBAC, log health, plus functional probes (a real audit report, a real enforce rejection, a real mutation, a real generate). See [`scripts/validate-installation.sh`](scripts/validate-installation.sh).

## Demo deployment

`make deploy-demo` — populates `kyverno-demo` with `demo/applications/` (one intentionally-incomplete "real" workload), `demo/insecure-workloads/` (13 individually-labeled, controlled-insecure fixtures), and `demo/compliant-workloads/` (corrected references) — deployed *without* policy enforcement yet, so labs/lab-02 can show the audit→enforce transition against real, already-existing resources.

## Lab sequence

18 labs, `labs/lab-00-prerequisites.md` through `labs/lab-17-production-readiness.md` — installation, audit-vs-enforce, every policy type, context/preconditions/JMESPath, troubleshooting, production readiness. Each lab is a self-contained, runnable walkthrough with exact commands and expected output; concept depth lives in `docs/`, referenced from each lab rather than repeated.

## Policy directories

| Directory | Contents |
| --- | --- |
| `policies/audit/` | Audit-mode twin of the enforce policy below |
| `policies/validate/` | Required labels, resource limits, privileged/host-namespace/capability/hostPath restrictions, registry allowlist, tag pinning |
| `policies/mutate/` | Default labels, default securityContext |
| `policies/generate/` | Default NetworkPolicy per labeled namespace |
| `policies/cleanup/` | Narrowly-scoped, namespaced cleanup of lab-marker test resources |
| `policies/verify-images/` | Keyless signature verification (Kyverno's own images) |
| `policies/exceptions/` | One narrowly-scoped, by-name PolicyException |
| `policies/advanced/` | ConfigMap context, in-cluster API-call context, foreach/precondition/JMESPath examples |
| `policies/production-examples/` | LoadBalancer restriction, required health probes |

Full inventory table below.

## Offline testing

`make test-static` (`tests/static-validation.sh`): `bash -n`/ShellCheck, YAML structural validation, `helm lint`, Kyverno CLI `kyverno test` against `tests/cli-test-cases/` (no cluster required), policy-quality checks (API versions, duplicate names, descriptions/messages, unsafe wildcards, image-tag hygiene), markdown links, `make help`. See root [`docs/DECISIONS.md`](../docs/DECISIONS.md) ADR-015.

## Runtime testing

`make test-runtime` (`scripts/run-tests.sh` → `tests/installation-test.sh` + one script per policy type) — requires a live, verified cluster. Every runtime test uses a uniquely-named or the `kyverno-demo` namespace, labels every resource it creates, cleans up via `trap` even on failure, and never touches a system namespace or an unrelated resource. See [`tests/expected-results.md`](tests/expected-results.md).

## Audit vs. enforce

Every enforce-mode policy in this lab has (or started as) a separate audit-mode policy file — see [`labs/lab-02-audit-vs-enforce.md`](labs/lab-02-audit-vs-enforce.md) and root [`docs/DECISIONS.md`](../docs/DECISIONS.md) ADR-013.

## Reports

`make reports` (`scripts/collect-policy-reports.sh`) summarizes `PolicyReport`/`ClusterPolicyReport` data, jq-summarized when available. No Grafana or Prometheus is installed or required by this independent lab — see [`docs/10-policy-reports.md`](docs/10-policy-reports.md) "Metrics and future observability integration" for Kyverno's own `/metrics` endpoints, documented but not scraped here. An optional Policy Reporter UI install exists at `install/optional/policy-reporter-values.yaml`, off by default (`config/lab-settings.env`'s `ENABLE_POLICY_REPORTER`).

## Cleanup

```bash
make clean-demo       # remove kyverno-demo + any temp lab namespaces (Kyverno itself untouched)
make clean-policies   # remove applied lab policies (Kyverno itself untouched)
make clean             # both of the above
```

## Uninstallation

```bash
make uninstall                    # removes the Helm release + namespace; CRDs kept by default
REMOVE_CRDS=true make uninstall   # DESTRUCTIVE — also deletes every Kyverno CRD cluster-wide (every
                                    # ClusterPolicy/Policy/PolicyException/PolicyReport, not just this lab's own)
```

Never touches Cilium, Hubble, kube-proxy, or the cluster itself.

## Troubleshooting

[`docs/14-troubleshooting.md`](docs/14-troubleshooting.md) — decision tree plus a 27-row symptom/diagnostic/cause/action/fix/validation table. [`labs/lab-16-troubleshooting.md`](labs/lab-16-troubleshooting.md) lets you trigger several of these yourself, safely.

## Production considerations

High availability (replica counts, PDB, anti-affinity, failure-policy trade-offs), governance (ownership, audit-first rollout, exception review), performance/scaling, and disaster recovery — [`docs/11-production-design.md`](docs/11-production-design.md), [`docs/12-security-and-governance.md`](docs/12-security-and-governance.md), [`docs/13-performance-and-scaling.md`](docs/13-performance-and-scaling.md).

## Security limitations

- The `kyverno-demo` namespace runs Pod Security Admission at `privileged` (i.e., no PSA restriction there) *by design* — it's where this lab's intentionally-insecure fixtures live so Kyverno itself can be shown rejecting them. Do not treat this namespace's PSA posture as a template for a real application namespace.
- This lab's default policies are `Audit` mode (see `spec.validationFailureAction` in each `policies/validate/*.yaml`) — audit-mode policies **report but never block**. Flipping to Enforce is a deliberate, documented step in each relevant lab, not the default state.
- The one `PolicyException` shipped here (`policies/exceptions/allow-demo-hostpath-exception.yaml`) is scoped to exactly one named resource for teaching purposes — treat it as a worked example, not a template to copy-paste broadly.
- No private registry credentials are required or stored anywhere in this module.

## Local-lab limitations

- `verify-images`'s keyless path depends on outbound network access to Sigstore's Rekor — offline/restricted-network environments can validate policy *syntax* but not live signature enforcement (docs/08-image-verification.md).
- `CleanupPolicy`'s 1-hour age condition means the automated runtime test cannot practically wait for a real deletion cycle — it validates the policy's readiness and selector scoping instead, documented explicitly rather than claiming a full end-to-end deletion test (`tests/cleanup-policy-tests.sh`).
- This lab's resource-request values (`install/values-*.yaml`) are lab-sized starting points, not load-tested production guidance (docs/13-performance-and-scaling.md).

## Definition of done

See root [`../PROJECT-IMPLEMENTATION-PLAN.md`](../PROJECT-IMPLEMENTATION-PLAN.md) Phase 3 and root [`../docs/VALIDATION-STATUS.md`](../docs/VALIDATION-STATUS.md) for the authoritative, current status — including exactly what has and hasn't been validated against a live cluster.

## Next module

```text
Phase 4: Independent Istio hands-on lab (../istio/)
```

See root [`../docs/LAB-WORKFLOW.md`](../docs/LAB-WORKFLOW.md) for the full recommended sequence and when to reuse vs. reset the base cluster between modules.

---

## Policy inventory

| Policy | Type | Mode | Scope | Lab |
| --- | --- | --- | --- | --- |
| `require-labels-audit` | validate | Audit | Pod, cluster-wide | lab-02, lab-03 |
| `require-labels-enforce` | validate | Enforce | Pod, cluster-wide | lab-02, lab-03 |
| `require-resource-limits` | validate | Audit | Pod, cluster-wide | lab-04 |
| `restrict-privileged-containers` | validate | Audit | Pod, cluster-wide | lab-05, lab-10, lab-16 |
| `restrict-image-registries` | validate | Audit | Pod, cluster-wide | lab-03 (referenced), production-examples |
| `restrict-latest-tag` | validate | Audit | Pod, cluster-wide | lab-05 (referenced) |
| `add-default-labels` | mutate | n/a | Pod, cluster-wide | lab-06, lab-12 |
| `add-security-context-defaults` | mutate | n/a | Pod, cluster-wide | lab-07 |
| `default-network-policy` | generate | n/a | Namespace → NetworkPolicy | lab-08 |
| `cleanup-lab-marker-pods` | cleanup | n/a | Pod, kyverno-demo only | lab-13 |
| `verify-image-signature` | verifyImages | Audit | Pod (ghcr.io/kyverno/* only), cluster-wide | lab-11 |
| `allow-demo-hostpath-exception` | exception | n/a | 1 named Pod, kyverno-demo only | lab-10, lab-16 |
| `validate-environment-against-configmap` | advanced (validate + context) | Audit | Pod, cluster-wide | lab-14 |
| `limit-deployments-per-namespace` | advanced (validate + context) | Audit | Deployment, cluster-wide | lab-14 |
| `precondition-examples` | advanced (validate + foreach/preconditions) | Audit | Deployment, cluster-wide | lab-15 |
| `deny-loadbalancer-services` | production-examples | Audit | Service, cluster-wide | lab-17 |
| `require-probes-production` | production-examples | Audit | Deployment, cluster-wide | lab-17 |
