# Expected Test Results

What a healthy run of each script in this directory looks like, so you can tell a real failure from noise. See [`../docs/VALIDATION-STATUS.md`](../../docs/VALIDATION-STATUS.md) (root) for what has actually been run against a live cluster so far in this repository (as of Phase 2: nothing — static checks only, see that document).

## `shellcheck.sh`

```text
==> bash -n (syntax check) on 27 scripts
[PASS] bash -n scripts/guest/00-common.sh
...
==> shellcheck on 27 scripts
[PASS] shellcheck scripts/guest/00-common.sh
...
```

Exit 0. A `[WARN] shellcheck is not installed...` line is expected and non-fatal on a host without ShellCheck — only `bash -n` ran in that case.

## `vagrant-validation.sh`

```text
==> ruby -c Vagrantfile
Syntax OK
[PASS] Vagrantfile is syntactically valid Ruby
==> vagrant validate
Configuration validated!
[PASS] 'vagrant validate' accepted the Vagrantfile
==> YAML template structural checks (config/*.yaml.tpl)
[PASS] YAML structure valid (post-placeholder-substitution): config/kubeadm-config.yaml.tpl
[PASS] YAML structure valid (post-placeholder-substitution): config/kubeadm-join-config.yaml.tpl
[PASS] YAML structure valid (post-placeholder-substitution): config/cilium-values.yaml.tpl
```

Exit 0. Never creates a VM.

## `cluster-smoke-test.sh` (requires a live cluster)

Before `make setup` has ever run:

```text
[INFO] No kubeconfig at .../auto-setup-default-kube-env/.generated/kubeconfig — cluster has not been provisioned. Nothing to smoke-test. Run 'make setup' first.
```

Exit 0 — this is expected, not a failure. After a successful `make setup`:

```text
[PASS] cluster-smoke-test: pod scheduled and reached Ready.
```

## `network-test.sh` (requires a live cluster with Cilium ready)

```text
==> Deploying test pods (worker1: pod-a, pod-b; worker2: pod-c)
[PASS] Pod-to-pod, same node (pod-b -> pod-a)
[PASS] Pod-to-pod, cross node (pod-c -> pod-a)
[PASS] Pod-to-Service (pod-b -> svc-a ClusterIP DNS)
[PASS] DNS resolution (kubernetes.default)
[PASS] Internet egress from a pod
[PASS] API Service connectivity from a pod
==> CiliumNetworkPolicy enforcement (deny pod-a's ingress, then remove)
[PASS] CiliumNetworkPolicy blocked ping to pod-a as expected.
==> Hubble visibility for the denied flow (best-effort)
[PASS] Hubble shows at least one DROPPED flow for network-test.
```

A `[WARN]` on the Hubble visibility line alone is non-fatal — the CiliumNetworkPolicy enforcement check above it is the mandatory signal.

## `storage-test.sh` (requires a live cluster with storage installed)

```text
==> 1. Create PVC
==> 2. Create pod mounting the PVC
[PASS] PVC bound and pod mounting it reached Ready.
==> 3. Write test data
==> 4. Read test data back
[PASS] Read back: persisted-data-1753500000
==> 5. Restart the pod
==> 6. Confirm data persistence after restart
[PASS] Data persisted across pod restart: 'persisted-data-1753500000'
==> 7. Clean up test resources
[INFO] Namespace storage-test deletion requested.
```

## Interpreting a mix of PASS/WARN/FAIL

- Any `[FAIL]` line means `scripts/host/validate-cluster.sh` (which calls into these) will exit non-zero. Investigate via [`../docs/TROUBLESHOOTING.md`](../docs/TROUBLESHOOTING.md) before re-running.
- `[WARN]` lines never fail the run by themselves — they flag below-recommended conditions or best-effort checks (e.g. Hubble CLI not installed) that don't block the environment from being usable.
- `[INFO]` lines that say a cluster "has not been provisioned" or "is not currently up" from the runtime tests are the correct, honest response when you run these tests before `make setup` — they are not silently skipped, they tell you why.
