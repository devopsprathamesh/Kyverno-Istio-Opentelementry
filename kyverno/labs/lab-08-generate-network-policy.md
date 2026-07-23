# Lab 08: Generate a Default NetworkPolicy

Concept background: docs/07-generate-and-cleanup-policies.md, `../../auto-setup-default-kube-env/docs/CILIUM-HUBBLE.md`.

## Objective

Generate a standard Kubernetes `NetworkPolicy` when a Namespace is labeled `generate-default-networkpolicy=enabled`, and understand how it interacts with Cilium underneath.

## 1. Apply

```bash
kubectl apply -f policies/generate/default-network-policy.yaml
```

## 2. Trigger it

```bash
kubectl create namespace lab08-test
kubectl label namespace lab08-test generate-default-networkpolicy=enabled
kubectl get networkpolicy -n lab08-test
```

Expected: `default-namespace-policy` appears within a few seconds — namespace intra-traffic + DNS egress allowed, everything else denied by default.

## 3. Synchronization

```bash
kubectl delete networkpolicy default-namespace-policy -n lab08-test
kubectl get networkpolicy -n lab08-test
```

Expected: it comes back — `synchronize: true` means Kyverno's background controller treats manual deletion as drift to correct, not a change to honor.

## 4. Negative case — no trigger label, no NetworkPolicy

```bash
kubectl create namespace lab08-negative
kubectl get networkpolicy -n lab08-negative
```

Expected: empty — the trigger label was never set.

## Standard Kubernetes NetworkPolicy vs. Cilium enforcement

This policy generates a plain `networking.k8s.io/v1` `NetworkPolicy`, not a `CiliumNetworkPolicy`. Cilium (this cluster's CNI) enforces standard `NetworkPolicy` objects natively — no Cilium-specific CRD is required for this basic default-deny pattern. See `../../auto-setup-default-kube-env/docs/CILIUM-HUBBLE.md` "CiliumNetworkPolicy and Kubernetes NetworkPolicy" for when you *would* reach for `CiliumNetworkPolicy` instead (L7-aware rules, DNS-aware egress, cluster-wide non-namespaced policies) — none of which this basic lab needs.

## Generated-resource ownership

Never hand-edit `default-namespace-policy` directly and expect it to stick — it will revert (step 3). The actual source of truth is this policy's `generate.data` block; changing intended behavior means changing the policy, then letting synchronization propagate it.

## Automated version

```bash
bash tests/generate-policy-tests.sh
```

## Cleanup

```bash
kubectl delete namespace lab08-test lab08-negative --wait=false
kubectl delete -f policies/generate/default-network-policy.yaml
```

## Next

`labs/lab-09-policy-reports.md`.
