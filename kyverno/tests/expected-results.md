# Expected Test Results

What a healthy run of each test in this directory looks like. See [`../../docs/VALIDATION-STATUS.md`](../../docs/VALIDATION-STATUS.md) (root) for what has actually been run in this repository so far — as of Phase 3, only the static (cluster-free) suite.

## `static-validation.sh` (`make test-static`, cluster-free)

```text
==> 1. bash -n and ShellCheck
[PASS] bash -n check-prerequisites.sh
...
==> 2. YAML structural validation
[PASS] All 33 YAML files parse.
==> 3. Helm values syntax and helm lint
[PASS] helm lint values-minimum.yaml
[PASS] helm lint values-recommended.yaml
==> 4. Kyverno CLI offline policy tests
[PASS] kyverno test tests/cli-test-cases/
==> 5. Policy quality checks
[PASS] require-labels-audit.yaml: current API version (kyverno.io/v1)
...
[PASS] No duplicate policy names across policies/.
==> 6. Unsafe wildcard / namespace-exclusion checks
[PASS] No policy matches all kinds via a bare wildcard.
==> 7. Image tag hygiene
[PASS] No unexpected ':latest' image tags outside intentionally-insecure fixtures.
==> 8. Markdown link check
[PASS] All relative markdown links in kyverno/ resolve.
==> 9. Makefile help
[PASS] make help succeeded, listing 20 targets.
```

A `[SKIP]` line for step 3 or 4 is expected and non-fatal on a host without `helm` network access to the chart repo, or without the Kyverno CLI installed — the reason is always printed, never silently omitted.

## `installation-test.sh` (requires a live cluster)

```text
[PASS] Namespace 'kyverno' exists
[PASS] Helm release 'kyverno' exists
[PASS] Deployment kyverno-admission-controller available
[PASS] Deployment kyverno-background-controller available
[PASS] Deployment kyverno-cleanup-controller available
[PASS] Deployment kyverno-reports-controller available
[PASS] At least one validating webhook present
[PASS] At least one mutating webhook present
```

Before `make install` has ever run: `[INFO] No reachable cluster — installation-test skipped (not a failure...)`, exit 0.

## `validate-policy-tests.sh`

```text
[PASS] Compliant Pod admitted as expected.
[PASS] Noncompliant Pod correctly rejected.
```

## `mutate-policy-tests.sh`

```text
[PASS] Missing 'environment' label was added (value: lab).
[PASS] Pre-set 'environment=production' label was left untouched (addIfNotPresent worked).
```

## `generate-policy-tests.sh`

```text
[PASS] Generate policy created the expected NetworkPolicy.
[PASS] synchronize: true correctly recreated the deleted NetworkPolicy.
[PASS] Namespace without the trigger label correctly got no generated NetworkPolicy.
```

## `cleanup-policy-tests.sh`

```text
[PASS] CleanupPolicy is Ready and its selector correctly targets only lab-marker=intentionally-insecure Pods (confirmed via match spec, not a live 1h-aged trigger).
[PASS] Unmarked Pod is untouched immediately after CleanupPolicy apply (no unexpected immediate deletion).
```

This test deliberately does NOT wait for a real 1-hour-aged deletion cycle — see the script's own `[INFO]` line and labs/lab-13-cleanup-policies.md for how to observe one manually.

## `exception-tests.sh`

```text
[PASS] Exempted resource 'demo-approved-hostpath-reader' was admitted despite the hostPath rule.
[PASS] A differently-named Pod with the same hostPath pattern was correctly still rejected — the exception is scoped to exactly one resource name.
```

## `image-verification-tests.sh`

```text
[PASS] Policy applied and reports Ready — syntax/admission is valid.
[PASS] An image outside this policy's scope (registry.k8s.io/*) is unaffected, as expected.
```

Real keyless signature enforcement against a live `ghcr.io/kyverno/*` pull is **not** exercised automatically by this script (requires outbound network to Rekor/Fulcio) — see the script's own `[INFO]` line and labs/lab-11-image-verification.md.

## Interpreting results

- Any `[FAIL]` line means the calling script (and `make test-runtime` / `make test-static`) exits non-zero. Check [`../docs/14-troubleshooting.md`](../docs/14-troubleshooting.md).
- `[WARN]` never fails a run by itself.
- `[INFO]`/`[SKIP]` lines that explain why something wasn't tested (no cluster, tool not installed, network-dependent case) are the honest, correct response — not a silently-dropped check.
