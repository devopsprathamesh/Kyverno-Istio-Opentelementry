# Lab 00: Prerequisites

## Objective

Get every tool this lab needs installed and confirmed working, and confirm you have a reachable, correctly-identified cluster, before touching any policy.

## 1. Base cluster

This module never provisions Kubernetes itself. If you haven't already:

```bash
cd ~/github/Kyverno-Istio-Opentelementry/auto-setup-default-kube-env
make prerequisites
make setup LAB_PROFILE=recommended
make validate
export KUBECONFIG="$(pwd)/.generated/kubeconfig"
```

## 2. Required tools

```bash
cd ~/github/Kyverno-Istio-Opentelementry/kyverno
make prerequisites
```

This checks `kubectl`, `helm`, `git`, `make`, `curl`, the Kyverno CLI (optional but recommended), and `cosign` (optional, only for lab 11's runtime path). It never installs anything — it tells you what's missing.

## 3. Installing the Kyverno CLI

Not required for cluster installation itself, but required for every offline (`make test-static`) exercise in this lab. Pinned version: see `config/versions.env`'s `KYVERNO_CLI_VERSION`.

```bash
# Linux amd64 example — check https://github.com/kyverno/kyverno/releases
# for your platform's exact asset name at the pinned version.
KYVERNO_CLI_VERSION="$(grep KYVERNO_CLI_VERSION config/versions.env | cut -d= -f2 | tr -d '"')"
curl -fsSL -o /tmp/kyverno-cli.tar.gz \
  "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_CLI_VERSION}/kyverno-cli_${KYVERNO_CLI_VERSION}_linux_x86_64.tar.gz"
tar -xzf /tmp/kyverno-cli.tar.gz -C /tmp
install -m 0755 /tmp/kyverno /usr/local/bin/kyverno   # or ~/.local/bin if you prefer a user-local install
kyverno version
```

## 4. Confirm cluster identity

```bash
make verify-cluster
```

This confirms: the API server is reachable, its endpoint matches `192.168.56.10` (the base platform's control plane), and all three expected nodes (`otel-control-plane`, `otel-worker-1`, `otel-worker-2`) exist. It refuses to proceed — and every other `make install`/runtime target depends on this passing first — if any of that doesn't match, so this module never installs into the wrong cluster.

## Expected output

```text
[PASS] All mandatory prerequisite checks passed.
[PASS] API server is reachable.
[PASS] API server references the expected endpoint (192.168.56.10).
[PASS] All 3 expected nodes present: otel-control-plane otel-worker-1 otel-worker-2
[PASS] Cluster identity confirmed: this is the intended local learning cluster (devops-learning-lab).
```

## Next

`labs/lab-01-install-kyverno.md`.
