# Lab 00: Prerequisites

## Objective

Confirm your environment is ready before installing anything — no cluster changes in this lab.

## Concepts exercised

Cluster-identity verification, tool prerequisites, the image-build/import path this module depends on (`docs/DECISIONS.md` ADR-030).

## Prerequisites

- A running cluster matching `config/endpoints.env`'s expected identity, provisioned by `../auto-setup-default-kube-env/` (not this module).
- `kubectl`, `helm`, `python3`.
- `docker` or `podman`, and `vagrant` — only required for `make build-demo-images` (labs 8 onward); everything through lab 07 works without them.

## Steps

1. **Check prerequisite tooling**:
   ```bash
   cd opentelemetry-prometheus-grafana-jaeger-loki
   make prerequisites
   ```

2. **Verify cluster identity**:
   ```bash
   make verify-cluster
   ```
   Hard-fails on API-endpoint/node-name/Cilium/kube-proxy/CoreDNS/StorageClass mismatch.

3. **Confirm image-build tooling** (needed from lab 08 onward):
   ```bash
   command -v docker || command -v podman
   command -v vagrant
   ```
   If neither is present, you can still complete labs 1–7 and read every doc/lab; `make build-demo-images`/`make deploy-demo` and everything downstream will need this resolved first.

## Validation

`make prerequisites` and `make verify-cluster` both exit 0, or print an actionable next step.

## Cleanup

None — this lab makes no cluster changes.

## Reflection

Why does this module check for a container builder (`docker`/`podman`) AND `vagrant` specifically, rather than just checking for a container registry? (See `docs/DECISIONS.md` ADR-030 and `scripts/build-demo-images.sh`.)
