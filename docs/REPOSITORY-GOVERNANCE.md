# Repository Governance

This document defines conventions every module in this repository must follow. It is normative: later phases are expected to comply with this document rather than each inventing their own conventions.

## Directory ownership

Ownership is fixed and defined in [`ARCHITECTURE.md`](ARCHITECTURE.md#1-directory-ownership). A module must not install or manage resources that belong to another module's ownership (e.g., `istio/` automation must never install Kyverno). The only exception is `all-tools-integrated-lab/`, which may install all of them, but must reuse validated configuration rather than re-deriving it (ADR-004).

## Naming conventions

### Directory naming

- Top-level module directories use the exact names already established: `auto-setup-default-kube-env/`, `kyverno/`, `istio/`, `opentelemetry-prometheus-grafana-jaeger-loki/`, `all-tools-integrated-lab/`.
- Within a module, use `kebab-case` for subdirectories (e.g., `manifests/`, `helm-values/`, `demo-app/`).

### File naming

- `kebab-case.md` for documentation, `kebab-case.yaml`/`.yml` for Kubernetes/Helm manifests (prefer `.yaml`), `kebab-case.sh` for shell scripts.
- Numbered prefixes (`01-`, `02-`) are permitted where install/apply order matters and is not otherwise encoded in a Makefile target or script.

### Shell script conventions

- Every script starts with:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  ```

- Scripts must be reasonably idempotent: re-running a script against a cluster/tool already in the desired state must not error or duplicate resources. Use `kubectl apply` (not `create`), check-before-act patterns, or `helm upgrade --install` rather than assuming a clean slate.
- Any destructive command (`kubectl delete`, `helm uninstall`, `vagrant destroy`, disk-wiping operations) must be named explicitly in the script's own comments/output and, where practical, isolated into a clearly labeled `clean`/`destroy`/`uninstall` script rather than embedded silently inside a `setup`/`install` script.
- Scripts should print what they are about to do before doing it, especially for destructive operations.

### YAML conventions

- Two-space indentation, no tabs.
- Every Kubernetes manifest sets `metadata.namespace` explicitly (never rely on `kubectl`'s ambient `--namespace`/context default) except for genuinely cluster-scoped resources.
- Every image reference is pinned to an exact tag (or digest where available) per [ADR-010](DECISIONS.md#adr-010-version-pinning) — no `:latest`.

### Helm values conventions

- One values file per environment/profile (e.g., `values-minimum.yaml`, `values-recommended.yaml`), not inline `--set` flags buried in scripts, so the actual applied configuration is reviewable in git.
- Every `helm install`/`upgrade` invocation in scripts or Makefiles must pass an explicit `--version`.
- Secrets are never placed in values files committed to git (see Secret handling below).

### Kubernetes namespace conventions

- Namespaces follow the table in [`ARCHITECTURE.md`](ARCHITECTURE.md#planned-namespace-strategy). A module must create only the namespace(s) it owns.
- Namespace manifests/creation commands live in the owning module, not duplicated across modules.

### Makefile conventions

- Every module-level Makefile exposes a `make help` target as the default (first) target, listing available targets with a one-line description.
- Target names are consistent across modules of the same kind (see the target lists in [`PROJECT-IMPLEMENTATION-PLAN.md`](../PROJECT-IMPLEMENTATION-PLAN.md) and the root `README.md`); do not invent module-specific synonyms for the same operation (e.g., always `clean`, never `cleanup` in one module and `clean` in another).
- Destructive Makefile targets (`destroy`, `uninstall`, `clean`) must be documented in the module's README with exactly what they remove.

### Documentation conventions

- Use clear technical English suitable for a senior engineer; explain reasoning and trade-offs, not just steps.
- Avoid unexplained acronyms on first use within a document.
- Use relative repository links between documents, never absolute local filesystem paths or guessed external URLs.
- Mermaid diagrams must use valid syntax and include a short explanation immediately below the diagram.
- Clearly separate **planned** work from **tested/validated** work in every document — do not imply something has been validated unless [`VALIDATION-STATUS.md`](VALIDATION-STATUS.md) actually records that validation.
- Do not duplicate full step-by-step instructions across documents; link to the single owning document instead.

## Validation requirements

- Every module must define what "validated" means for it (health checks, smoke tests, expected resource states) and implement it as a `make validate` target once that phase is implemented.
- No document may claim a component is "tested" or "production-ready" without a corresponding entry in [`VALIDATION-STATUS.md`](VALIDATION-STATUS.md) describing what was actually run.

## Cleanup requirements

- Every module must provide a cleanup path (`make clean` and/or `make uninstall`) that removes everything it created: workloads, CRDs, namespaces it owns, and cluster-scoped resources (ClusterRoles, webhook configurations) it registered.
- Cleanup must be safe to run even if install only partially succeeded (idempotent, tolerant of already-missing resources).

## Security requirements

- No plaintext secrets, credentials, tokens, or private keys are ever committed, including inside Helm values files, example manifests, or documentation code blocks.
- Example/template files that must show a secret's *shape* use obviously fake placeholder values and are named to make that clear (e.g., `values.example.yaml`), and are excluded appropriately by `.gitignore` patterns where a real counterpart would be generated locally.
- Cluster-admin-equivalent RBAC is scoped down per module wherever the tool supports it; document any case where a tool genuinely requires cluster-admin and why.
- mTLS, AuthorizationPolicy, and NetworkPolicy configuration changes (Istio/Cilium) must be validated in the lab before being described as a "production pattern" in documentation.

## Git safety requirements

- Never force-push, rebase, or rewrite history on shared branches.
- Never commit generated, machine-specific, or secret-bearing files (see `.gitignore`); if a file was committed by mistake, remove it and rotate any exposed credential rather than only deleting it from a future commit.
- Destructive local git operations (`reset --hard`, `clean -f`, discarding uncommitted work) require explicit user confirmation in an interactive session; automation scripts in this repository must never run them against the repository itself.

## Generated-file handling

- Anything produced by running the labs (kubeconfig exports, Terraform/Vagrant state, Helm-generated manifests, downloaded CLI binaries) is generated output, not source, and must be excluded via `.gitignore` (see root `.gitignore` and the `.generated/` convention).
- If a generated artifact is genuinely useful to keep as a reference (e.g., a redacted example kubeconfig), commit an explicit `*.example` copy, never the real generated file.

## Secret handling

- kubeconfig files, TLS keys/certs, tokens, and `.env` files are excluded by the root `.gitignore` patterns (`*kubeconfig*`, `*.key`, `*.pem`, `*.p12`, `*.token`, `.env`, `*.env.local`).
- Any secret needed by a lab (e.g., a registry credential for a local container registry) is created imperatively at install time (`kubectl create secret ... --from-literal=...` run locally) and documented as a manual/scripted step — never checked into a values file or manifest.

## Version pinning requirements

See [ADR-010](DECISIONS.md#adr-010-version-pinning) and [`VERSIONS.md`](VERSIONS.md). Every version-bearing reference (VM box version, Helm chart `--version`, container image tag, CLI tool version) must be an exact pinned version, sourced from official documentation, and recorded in `VERSIONS.md` before it is used in any script or manifest.

## Cross-module reuse rules

- Independent labs (`kyverno/`, `istio/`, `opentelemetry-prometheus-grafana-jaeger-loki/`) must not reference or depend on each other's manifests, namespaces, or CRDs.
- `all-tools-integrated-lab/` must reuse already-validated configuration from the independent labs (by referencing/copying validated manifests, not regenerating equivalent-but-different configuration) and must document which artifacts were reused from which module.
- Shared, genuinely tool-neutral utilities (e.g., a generic "wait for pods ready" shell helper) may live in a common location once a real duplication is identified — do not pre-emptively create shared utility directories before that need is concrete.
