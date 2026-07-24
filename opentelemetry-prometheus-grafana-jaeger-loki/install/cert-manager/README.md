# cert-manager (documented, NOT installed by default)

This directory intentionally contains no install manifests. `make install-operator` uses the OpenTelemetry Operator Helm chart's built-in `admissionWebhooks.autoGenerateCert.enabled=true` path (Helm-native self-signed webhook certificate) instead of cert-manager — see `../opentelemetry-operator/values.yaml` and root `docs/DECISIONS.md` ADR-026.

## Why documented here at all

The Operator's webhook (used for `Instrumentation`-CRD auto-instrumentation injection) needs a TLS certificate one way or another. The chart supports three paths:

1. **cert-manager** (`admissionWebhooks.certManager.enabled=true`, the chart default) — a full, separate CRD-based certificate-management operator.
2. **Helm `autoGenerateCert`** (`admissionWebhooks.autoGenerateCert.enabled=true`) — a self-signed cert generated at install time by a Helm hook Job, no extra component installed.
3. Manual certificate injection (both disabled).

This module uses path 2. It avoids adding a second CRD-based operator dependency this lab does not otherwise need, keeping the module's actual footprint to exactly the 5 tools the phase is about.

## If you want the cert-manager path instead

Pinned version researched for this phase (2026-07-24): **cert-manager `v1.21.0`**, tested against Kubernetes 1.33–1.36 (covers this repo's pinned 1.35.6 base) — see root `docs/VERSIONS.md` "Phase 5 addendum". To use it:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.21.0 \
  --set crds.enabled=true

# Then install the Operator with the cert-manager path instead:
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry \
  --set admissionWebhooks.certManager.enabled=true \
  --set admissionWebhooks.autoGenerateCert.enabled=false \
  ...
```

Not scripted by this module — a manual, disclosed alternative for a learner who specifically wants cert-manager experience, not this lab's default path.
