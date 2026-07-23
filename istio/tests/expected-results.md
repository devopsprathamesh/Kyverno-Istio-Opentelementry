# Expected Test Results

What a healthy run of each script in this directory looks like. See [`../../docs/VALIDATION-STATUS.md`](../../docs/VALIDATION-STATUS.md) (root) for what has actually been run in this repository so far — as of Phase 4: static checks only, see that document.

## `static-validation.sh` (`make test-static`, cluster-free)

```text
==> 1. bash -n and ShellCheck            [PASS] x N scripts
==> 2. YAML structural validation        [PASS] All N YAML files parse.
==> 3. Helm lint                          [PASS] or [WARN]/[SKIP] if helm/network unavailable
==> 4. istioctl analyze / validate        [PASS] or [SKIP] if istioctl not installed
==> 5. Manifest quality checks            [PASS] No ':latest' tags; no duplicate names
==> 6. Deprecated API detection           [PASS] All Istio manifests use current API versions
==> 7. Markdown link check                [PASS] All relative markdown links in istio/ resolve.
==> 8. Makefile help                      [PASS] make help succeeded, listing N targets.
```

A `[SKIP]` for step 3 or 4 is expected and non-fatal without network/tool access — the reason is always printed.

## `installation-test.sh` (requires a live cluster)

```text
[PASS] Namespace 'istio-system' exists
[PASS] Namespace 'istio-ingress' exists
[PASS] Helm release 'istio-base' exists
[PASS] Helm release 'istiod' exists
[PASS] Helm release 'istio-cni' exists
[PASS] Helm release 'istio-ingress' exists
[PASS] Istio CNI DaemonSet healthy
[PASS] Ingress gateway deployment available
```

Before `make install` has run: `[INFO] No reachable cluster — installation-test skipped`, exit 0.

## `sidecar-injection-test.sh`

```text
[PASS] Sidecar injected as expected in labeled namespace.
[PASS] No sidecar injected in an unlabeled namespace, as expected (1 container).
```

## `ingress-test.sh`

```text
[PASS] Ingress gateway routed a request to frontend successfully.
```

## `traffic-routing-test.sh`

```text
[INFO] Observed distribution: v1=91 v2=9 (v2 = 9%, target 10% +/- 15%)
[PASS] Canary distribution within statistical tolerance.
```

## `retry-timeout-test.sh`

```text
[INFO] Response code: 504, elapsed: 1s (100% 3s delay vs. 1s VirtualService timeout)
[PASS] VirtualService timeout correctly cut off the delayed request before the full 3s delay (504 in 1s).
```

## `fault-injection-test.sh`

```text
[INFO] Observed abort rate: 16/50 (32%, target ~30%)
[PASS] Abort fault rate within statistical tolerance.
```

## `circuit-breaking-test.sh`

```text
[INFO] Results: 22 succeeded, 8 rejected (5xx, expected circuit-breaker overflow behavior)
[PASS] Connection-pool limits produced overflow rejections as expected...
```

A `[WARN]` (no overflow observed) is possible and non-fatal on a fast backend/small load — see the script's own note.

## `mtls-test.sh`

```text
[PASS] In-mesh (sidecar-injected) client succeeded under STRICT mTLS.
[PASS] Plaintext (non-mesh) client was correctly rejected under STRICT mTLS.
```

## `authorization-test.sh`

```text
[PASS] Unauthorized caller (wrong ServiceAccount identity) correctly denied (403) by AuthorizationPolicy.
[PASS] A different non-frontend in-mesh identity (test-client) is also correctly denied...
```

## `egress-test.sh`

```text
[PASS] Registered simulated-external host reachable, as expected.
```

## `cilium-compatibility-test.sh`

```text
[PASS] Cilium DaemonSet healthy
[PASS] Istio CNI DaemonSet healthy
[PASS] Cilium Helm values confirm CNI-chaining compatibility
[PASS] Sidecar-to-sidecar connectivity works through Cilium + Istio CNI chaining
```

If the Cilium CNI-chaining values check fails, see `docs/04-istio-cni-and-cilium.md` and `scripts/lib/istio.sh`'s `print_cilium_cni_chaining_remediation` for the exact manual remediation (this module never modifies Cilium itself).

## Interpreting results

- Any `[FAIL]` line means the calling script (and `make test-runtime`/`make test-static`) exits non-zero. Check [`../docs/14-troubleshooting.md`](../docs/14-troubleshooting.md).
- `[WARN]` never fails a run by itself.
- `[INFO]` lines explaining "no cluster" or "tool not installed" are the honest, correct response, not a silently-skipped check.
