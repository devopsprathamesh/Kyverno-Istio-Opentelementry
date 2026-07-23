# Lab 11: Image Verification

Concept background: docs/08-image-verification.md.

## Static/offline path (default — no opt-in needed)

### 1. Validate policy syntax without a cluster

```bash
kyverno apply policies/verify-images/verify-image-signature.yaml \
  -r demo/test-resources/compliant-pod.yaml
```

This confirms the policy itself is syntactically valid and its `verifyImages` block parses — it does not perform a real signature check offline (the fixture image, `registry.k8s.io/pause:3.10`, isn't even in this policy's `imageReferences` scope, so this is purely a syntax/dry-run check).

### 2. Apply on a live cluster and confirm scoping

```bash
kubectl apply -f policies/verify-images/verify-image-signature.yaml
kubectl get clusterpolicy verify-image-signature -o jsonpath='{.status.ready}'
kubectl run scope-check --image=registry.k8s.io/pause:3.10 -n kyverno-demo
```

Expected: admitted normally — this policy's `imageReferences` only match `ghcr.io/kyverno/*`, so an out-of-scope image is completely unaffected.

### 3. (Optional, requires outbound network to Rekor) real keyless verification

```bash
kubectl run kyverno-signed-test --image=ghcr.io/kyverno/kyverno:v1.18.2 -n kyverno-demo
```

If your network allows reaching `rekor.sigstore.dev`, this pulls and verifies Kyverno's own genuinely-signed image against the keyless attestor. If it doesn't (offline lab environment, restricted egress), expect a verification failure whose message distinguishes "couldn't reach Rekor" from "signature invalid" — read the actual controller log line, don't assume which one it is.

```bash
bash tests/image-verification-tests.sh
```

## Optional runtime signing path (Cosign, opt-in)

Only continue here if you want to see **static-key** verification specifically (as opposed to keyless), and are comfortable installing `cosign` locally.

### 1. Enable and prepare

```bash
# in your local .env (see ../.env.example):
# ENABLE_COSIGN_RUNTIME_LAB=true
mkdir -p .generated/cosign
cosign generate-key-pair --output-key-prefix .generated/cosign/lab-key
# Produces .generated/cosign/lab-key.key (private, NEVER commit) and
# .generated/cosign/lab-key.pub (public — this is what a static-key
# ClusterPolicy attestor would reference).
```

`.generated/` is git-ignored by the root `.gitignore`'s `.generated/`/`**/.generated/` patterns — confirm before proceeding:

```bash
cd ../.. && git check-ignore -q kyverno/.generated/cosign/lab-key.key && echo "correctly ignored" && cd kyverno
```

### 2. Sign a local test image reference and build a static-key policy

Follow Cosign's own documentation for signing a specific image reference you control (this requires push access to a registry you can write to — this lab does not provide one, since "no private registry credentials required for the default lab" per this module's design). Use the resulting signature to build a `attestors.entries[].keys.publicKeys` block referencing `.generated/cosign/lab-key.pub`'s contents, and confirm: the signed image is admitted, an unsigned image (or one signed with a different key) is rejected.

### 3. Clean up generated credentials

```bash
rm -rf .generated/cosign
```

Never commit anything under `.generated/cosign/` — this is exactly why it's git-ignored.

## Cleanup

```bash
kubectl delete -f policies/verify-images/verify-image-signature.yaml
kubectl -n kyverno-demo delete pod scope-check kyverno-signed-test --ignore-not-found
```

## Next

`labs/lab-12-background-scanning.md`.
