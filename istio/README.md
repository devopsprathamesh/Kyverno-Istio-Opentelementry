# istio

Independent, production-oriented Istio hands-on lab: service mesh fundamentals, Envoy/xDS internals, traffic management, mTLS/authorization/JWT security, resilience patterns, Cilium CNI-chaining, controlled failure scenarios, and automated static + runtime validation/cleanup — installable and removable without touching Kyverno, the observability stack, or the base Kubernetes platform.

## What Istio is

A service mesh: a control plane (Istiod) computing and distributing Envoy proxy configuration over xDS, and a data plane of per-workload Envoy sidecars enforcing routing, mTLS, and authorization in the network path itself. See [`docs/01-service-mesh-fundamentals.md`](docs/01-service-mesh-fundamentals.md) and [`docs/02-istio-architecture.md`](docs/02-istio-architecture.md).

## Why it is used

Kubernetes Services give you basic L3/L4 load balancing and nothing else — no retries, no mTLS, no per-request routing, no identity-based authorization. Istio adds all of that uniformly, at the network layer, without touching application code. See [`docs/01-service-mesh-fundamentals.md`](docs/01-service-mesh-fundamentals.md) "Problem being solved".

## Mode: sidecar only, Cilium CNI-chained

This lab runs Istio's **sidecar** data plane exclusively, with the **Istio CNI plugin chained** alongside this cluster's existing **Cilium** CNI (kube-proxy retained, matching root [`docs/DECISIONS.md`](../docs/DECISIONS.md) ADR-003). **Ambient mode is documented, not implemented** — see [`docs/16-future-ambient-mode.md`](docs/16-future-ambient-mode.md). Cilium and Istio CNI chaining has a real prerequisite gap on this repository's base platform — read [`docs/04-istio-cni-and-cilium.md`](docs/04-istio-cni-and-cilium.md) before your first `make install`.

## Architecture

Istiod (merged Pilot+Citadel+Galley functions), Envoy sidecars, Istio CNI DaemonSet, ingress gateway, revision-based install for future canary upgrades — see [`docs/02-istio-architecture.md`](docs/02-istio-architecture.md) and [`docs/03-envoy-and-sidecar-internals.md`](docs/03-envoy-and-sidecar-internals.md).

## Prerequisites

`kubectl`, `helm`, `istioctl` (checksum-verified, user-local install — `make install-istioctl`), and a reachable cluster. Run `make prerequisites` — see [`labs/lab-00-prerequisites.md`](labs/lab-00-prerequisites.md).

## Base cluster dependency

This module **never** provisions or destroys Kubernetes itself, never invokes Vagrant, and never modifies Cilium, kube-proxy, or CoreDNS. It depends entirely on [`../auto-setup-default-kube-env/`](../auto-setup-default-kube-env/) already being up. Every install/runtime target runs `verify-cluster` first, confirming the reachable cluster is genuinely the intended local learning cluster (API endpoint `192.168.56.10`, nodes `otel-control-plane`/`otel-worker-1`/`otel-worker-2`, Cilium and CoreDNS healthy) — not just "a cluster exists" — and refuses to proceed on a mismatch.

## Version matrix

| Component | Version | Source |
| --- | --- | --- |
| Istio (control plane, data plane, `istioctl`) | 1.30.3 | `istio.io` supported-releases |
| Istio Helm charts (`base`, `istiod`, `cni`, `gateway`) | 1.30.3 each | `istio-release.storage.googleapis.com/charts/index.yaml` |
| Kubernetes compatibility | 1.32–1.36 | Covers this repo's pinned base-platform version |
| Kubernetes Gateway API CRDs | v1.4.0 | `kubernetes-sigs/gateway-api` releases (installed conditionally, documented not exercised — see below) |

Full detail and sources: root [`docs/VERSIONS.md`](../docs/VERSIONS.md) "Phase 4 addendum". Centralized in [`config/versions.env`](config/versions.env).

## Quick start

```bash
cd ~/github/Kyverno-Istio-Opentelementry/auto-setup-default-kube-env
make setup LAB_PROFILE=recommended
make validate

export KUBECONFIG="$(pwd)/.generated/kubeconfig"

cd ../istio
make prerequisites
make install-istioctl        # if istioctl isn't already installed
make verify-cluster          # heed any Cilium CNI-chaining WARNING — see docs/04-istio-cni-and-cilium.md
make install LAB_PROFILE=recommended
make validate-installation
make deploy-demo
make status
```

## Installation

`make install` runs, in order: namespace → `base` chart (CRDs) → Gateway API CRDs (conditionally, ownership-tracked) → **Cilium CNI-chaining hard-check** → `istiod` → `istio-cni` → ingress `gateway`. See [`docs/02-istio-architecture.md`](docs/02-istio-architecture.md) and [`labs/lab-01-installing-istio.md`](labs/lab-01-installing-istio.md).

## Validation

`make validate-installation` — Helm release presence, CNI DaemonSet health, ingress gateway readiness, webhook presence. See [`tests/expected-results.md`](tests/expected-results.md).

## Demo deployment

`make deploy-demo` deploys `frontend → order-service → {inventory-service, payment-service}` (all `traefik/whoami`, pinned tag, non-root, resource-limited — see root [`docs/DECISIONS.md`](../docs/DECISIONS.md)'s demo-app-design ADR), `frontend`/`order-service` each with `v1`/`v2` Deployments for subset-routing labs, plus the ingress `Gateway`. Traffic/security/resilience/egress policy is deliberately **not** applied here — each lab applies its own so the effect is visible in isolation. See [`labs/lab-03-deploying-demo-app.md`](labs/lab-03-deploying-demo-app.md).

## Lab sequence

21 labs, `labs/lab-00-prerequisites.md` through `labs/lab-20-production-readiness.md` — installation, sidecar injection, Envoy internals, VirtualService/DestinationRule routing, canary/header routing, retries/timeouts/fault-injection/circuit-breaking/outlier-detection, strict mTLS, authorization policy, JWT authentication, egress control, Sidecar-resource scoping, xDS debugging, Cilium/Istio troubleshooting, and a production-readiness capstone. Each lab is self-contained with exact commands and expected output; concept depth lives in `docs/`, referenced from each lab. Full inventory table below.

## Lab inventory

| Lab | Topic |
| --- | --- |
| 00 | Prerequisites and environment verification |
| 01 | Installing Istio (sidecar mode, Cilium CNI-chained) |
| 02 | Sidecar injection |
| 03 | Deploying the demo application |
| 04 | Envoy internals exploration |
| 05 | VirtualService routing basics (exact/prefix/rewrite) |
| 06 | DestinationRule subsets |
| 07 | Canary traffic shifting |
| 08 | Header-based routing |
| 09 | Retries and timeouts |
| 10 | Fault injection |
| 11 | Circuit breaking (connection pool limits) |
| 12 | Outlier detection |
| 13 | Strict mTLS |
| 14 | Authorization policy |
| 15 | JWT authentication |
| 16 | Egress control (ServiceEntry) |
| 17 | Sidecar resource (egress scoping) |
| 18 | Debugging xDS (deliberate misconfiguration) |
| 19 | Cilium + Istio troubleshooting (controlled failure scenarios) |
| 20 | Production readiness review and teardown |

## Demo application

`frontend`/`order-service`/`inventory-service`/`payment-service`, all `traefik/whoami:v1.11.0` (pinned, non-`latest`), non-root, resource-limited, health-probed. No custom Dockerfiles or local registry — chosen deliberately so every lab exercises Istio's own traffic-management/resilience features against a real HTTP backend, not application logic. See [`demo/`](demo/) and root [`docs/DECISIONS.md`](../docs/DECISIONS.md).

## Manifest directories

| Directory | Contents |
| --- | --- |
| `install/` | Namespace, Helm values (`base`/`istiod`/`cni`/`gateway`, `minimum`/`recommended` profiles), Gateway API CRD reference |
| `demo/services/` | The four demo microservices |
| `demo/gateway/` | Ingress `Gateway` + base `VirtualService` |
| `demo/traffic/` | `DestinationRule` subsets, path/header/canary `VirtualService`s |
| `demo/resilience/` | Retries/timeouts, fault-injection (delay/abort) |
| `demo/egress/` | Simulated external service + `ServiceEntry` |
| `policies/peerauthentication/` | Permissive/strict mTLS |
| `policies/authorization/` | Default-deny + explicit allows + method/path restriction |
| `policies/requestauthentication/` | JWT template (inline JWKS, no remote IdP) |
| `policies/sidecar/` | Namespace-scoped egress `Sidecar` resource |

## Offline testing

`make test-static` (`tests/static-validation.sh`): `bash -n`/ShellCheck, YAML structural validation, `helm lint`, `istioctl analyze --use-kube=false` against every manifest, manifest-quality checks (no `:latest`, current API versions), markdown link check, `make help`. See [`tests/static-validation.sh`](tests/static-validation.sh).

## Runtime testing

`make test-runtime` (requires a live, verified cluster): installation checks plus sidecar-injection, ingress, traffic-routing, retry/timeout, fault-injection, circuit-breaking, mTLS, authorization, egress, and Cilium-compatibility test scripts. See [`tests/expected-results.md`](tests/expected-results.md) for what a healthy run looks like.

## Debugging

`istioctl analyze` → `istioctl proxy-status` → `istioctl proxy-config`, in that order — see [`docs/10-configuration-analysis.md`](docs/10-configuration-analysis.md) and [`docs/14-troubleshooting.md`](docs/14-troubleshooting.md). `make debug-bundle` collects a sanitized troubleshooting archive under `.generated/debug-bundles/`.

## Cleanup

`make clean-demo` / `make clean-config` / `make clean` (`scripts/clean.sh`) remove only demo namespaces and lab-applied config objects — the Istio installation itself is untouched. Everything this lab applies carries a lab-resource label so cleanup never touches anything it didn't create.

## Uninstallation

`make uninstall` (`scripts/uninstall.sh`) removes the Istio Helm releases and `istio-system`/`istio-ingress` namespaces, in reverse install order. CRDs are kept by default (`REMOVE_CRDS=true` to also remove them — cluster-wide, not just this lab's). Gateway API CRDs are only removed if this lab's own install tracked owning them (`.generated/gateway-api-crds-owned.marker`). **Never** touches Cilium, kube-proxy, or the cluster itself.

## Troubleshooting

Symptom-first reference table covering sidecar/injection, routing, security, resilience, egress, and Cilium/CNI-chaining issues: [`docs/14-troubleshooting.md`](docs/14-troubleshooting.md).

## Production considerations

What this lab implements at small scale versus what a real production mesh additionally needs (HA sizing, mesh-wide `REGISTRY_ONLY` egress, real IdP integration, canary control-plane upgrades) — stated explicitly, not left implied: [`docs/11-production-design.md`](docs/11-production-design.md).

## Security limitations of this lab

Inline JWKS instead of a real IdP's `jwksUri` (avoids a live external dependency during labs), self-signed root CA (Istiod-generated, not an external CA integration), and a single simulated (not real) external egress target — all deliberate, all documented, none silently assumed production-appropriate. See [`docs/06-service-security-and-mtls.md`](docs/06-service-security-and-mtls.md) and [`docs/11-production-design.md`](docs/11-production-design.md).

## Local-lab limitations

`ClusterIP` + port-forward ingress access (no cloud `LoadBalancer` on this bare-metal Vagrant cluster — root [`docs/DECISIONS.md`](../docs/DECISIONS.md) ADR-023), no load-testing/benchmarking harness (`docs/12-performance-and-capacity.md`), single Istio revision installed (upgrade-*ready*, not upgrade-*exercised* — `docs/13-upgrades-and-disaster-recovery.md`).

## Interview preparation

40 scenario-driven questions, cross-referenced to the exact concept doc and lab that answers each one: [`docs/15-interview-scenarios.md`](docs/15-interview-scenarios.md).

## Definition of done

Fully implemented and statically validated (manifests, scripts, `istioctl analyze`, ShellCheck, YAML structural checks). **Runtime validation against a live cluster is pending** — no cluster was available at authoring time; see root [`docs/VALIDATION-STATUS.md`](../docs/VALIDATION-STATUS.md) for the exact commands to run once one exists (`make verify-cluster` → `make install` → `make validate-installation` → `make deploy-demo` → `make test-runtime`).

## Next module

**Phase 5** adds observability (Kiali, Prometheus, Grafana, Jaeger, Loki) on top of this mesh — explicitly **not** started, not scoped, and not touched by this module. Nothing in `istio/` installs, configures, or assumes any observability tooling.

## Concept doc inventory

16 documents, `docs/01-service-mesh-fundamentals.md` through `docs/16-future-ambient-mode.md`, 16 Mermaid diagrams total. Each follows: Definition → Problem being solved → Kubernetes-native behavior → detailed mechanics → diagram(s) → Failure modes → Production considerations → Interview-level explanation.

## Examples

[`examples/application-access.md`](examples/application-access.md) (reaching the demo app and ingress), [`examples/curl-test-commands.md`](examples/curl-test-commands.md) (copy-pasteable test commands per concept), [`examples/profile-overrides.env.example`](examples/profile-overrides.env.example) (what `LAB_PROFILE` actually changes).
