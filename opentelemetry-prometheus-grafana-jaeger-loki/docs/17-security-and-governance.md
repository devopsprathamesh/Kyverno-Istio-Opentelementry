# Security and Governance

## Definition

What this lab actually does to keep a local, single-tenant observability stack reasonably safe by default, and — just as important — what it explicitly does NOT implement, stated directly rather than left for a learner to assume.

## What this lab implements

**Non-root containers** — every Dockerfile in `demo-application/` sets a non-root `USER`; the Collector Agent/Gateway run as UID 10001 (`collector/agent/daemonset.yaml`, `collector/gateway/deployment.yaml`). **Read-only root filesystems** — set on every container except where the Operator's auto-instrumentation init container genuinely needs to write into the app container's filesystem (`frontend`, `inventory-service` — documented exceptions, not oversights). **Least-privilege RBAC** — `collector/agent/clusterrole.yaml`/`gateway/clusterrole.yaml` grant only `get`/`list`/`watch` on exactly `pods`/`namespaces`/`replicasets`, nothing else, no write verbs anywhere. **Read-only host log mounts** — `collector/agent/daemonset.yaml`'s `/var/log/pods` hostPath is mounted `readOnly: true`. **No public UI exposure** — every backend's Service is `ClusterIP`; access is exclusively via `make port-forward-*`, localhost-bound. **No committed credentials** — Grafana's admin password is randomly generated into `.generated/` (git-ignored) by `scripts/install-grafana.sh`, never hardcoded. **Sensitive-field filtering** — `collector/gateway/configmap.yaml`'s `attributes/redact` processor deletes `password`/`token`/`card_number`/`customer.ssn`/`http.request.header.authorization` from every pipeline before export.

## What this lab does NOT implement (stated explicitly)

**TLS between Collector hops** — `tls: {insecure: true}` throughout `collector/*/configmap.yaml`, justified only because every hop is in-cluster (Agent→Gateway, Gateway→backends) on this single-tenant lab cluster; see "TLS and mTLS for OTLP" below for the production alternative. **OTLP authentication** — no API-key/bearer-token requirement on any OTLP receiver in this lab; anything that can reach the Collector's ports in-cluster can send telemetry. **Multi-tenancy** — Loki runs `auth_enabled: false` (`14-loki-architecture.md`); every log stream shares one implicit tenant. **SSO/OAuth for Grafana** — basic auth with a generated password only.

## Traditional implementation

Pre-Kubernetes, "security" for an observability stack often meant network-perimeter-only controls (a firewall around the monitoring VLAN) with no per-component least-privilege discipline — a single compromised component had broad blast radius.

## OpenTelemetry / Kubernetes implementation

Kubernetes RBAC (ServiceAccounts scoped per-component, `collector/agent/serviceaccount.yaml` distinct from `gateway/serviceaccount.yaml`, each with its own narrowly-scoped `ClusterRole`) is this lab's primary least-privilege mechanism — no component shares another's identity or permissions.

## Internal processing flow

The `attributes/redact` processor runs in the Gateway, applied to every pipeline (traces/metrics/logs) before the corresponding exporter — see `collector/gateway/configmap.yaml`'s pipeline wiring; redaction happens once, centrally, rather than being each application's own responsibility to remember.

## Kubernetes implementation: RBAC read directly

```bash
kubectl get clusterrole otel-collector-agent -o yaml
kubectl auth can-i '*' '*' --as=system:serviceaccount:opentelemetry:otel-collector-agent -A   # expect 'no'
```

## Working configuration

`collector/gateway/configmap.yaml`'s `attributes/redact` processor — the real, complete list of redacted keys.

## Validation commands

See above, plus:
```bash
kubectl get pod -n otel-demo -l app=order-service -o jsonpath='{.spec.securityContext}'
```

## OTLP authentication options for production

Real options this lab doesn't implement: mTLS client certificates (the Collector's `otlp` receiver supports `tls.client_ca_file` for mutual TLS), a bearer-token `headers_setter`/auth extension pairing, or network-policy-based restriction (e.g. Cilium `CiliumNetworkPolicy`, available on this cluster's CNI but not applied by this lab to the `opentelemetry` namespace — `docs/21-troubleshooting.md` "NetworkPolicy block" covers the failure mode if one *were* misconfigured, even though none exists by default here).

## TLS and mTLS for OTLP

Production guidance: terminate TLS at minimum between untrusted network boundaries (any hop crossing outside the cluster or outside a trusted namespace), and consider full mTLS (mutual authentication, both directions) between the Collector and its backends if those backends are shared/multi-tenant infrastructure. This lab's `insecure: true` throughout is a deliberate, scoped simplification — every hop stays inside one cluster's `opentelemetry`/`observability` namespaces, not a general recommendation.

## Multi-tenancy limitations, stated for both Loki and Grafana

Loki: single implicit tenant, no per-team isolation of log data or query access. Grafana: single admin account, no per-team RBAC on dashboards/data sources. A real multi-team production deployment needs both addressed — Loki's tenant ID mechanism and Grafana's org/team/RBAC features both exist and are real, documented, just not configured here.

## Failure modes

- Assuming `insecure: true` in `collector/*/configmap.yaml` is an oversight rather than a deliberate, scoped, documented choice — it's the latter; re-read this doc's "TLS and mTLS" section before "fixing" it without considering what problem you're actually solving.
- A `NetworkPolicy` (Cilium or otherwise) applied to the `opentelemetry`/`observability` namespaces without accounting for the Agent↔Gateway↔backend traffic pattern — would silently break the pipeline; `docs/21-troubleshooting.md` "NetworkPolicy block."

## Production considerations

This document's "What this lab does NOT implement" list *is* the production checklist — treat it as such rather than as a list of oversights.

## Interview-level explanation

*"What security shortcuts does this lab take, and are they justified?"* — Plaintext (non-TLS) OTLP between Collector hops, no OTLP authentication, single-tenant Loki/Grafana, and a locally-generated (not vault-managed) Grafana admin password. Each is justified specifically by scope: every one of these hops stays inside a single-tenant, single-cluster lab environment with no public exposure (every UI is `ClusterIP`-only, reached via port-forward). None of these choices would be defensible in a real multi-tenant or externally-reachable production deployment — and this document says so explicitly, rather than leaving a learner to assume lab defaults are production-safe.
