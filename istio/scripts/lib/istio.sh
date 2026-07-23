#!/usr/bin/env bash
# Istio/istioctl-specific helpers. Source this file, never execute it
# directly. Assumes common.sh and kubernetes.sh have already been
# sourced.
set -euo pipefail

istioctl_available() {
  command -v istioctl >/dev/null 2>&1
}

# cilium_cni_chaining_ready — checks whether the LIVE Cilium Helm
# release has the values Istio CNI chaining requires
# (cni.exclusive=false, socketLB.hostNamespaceOnly=true — see
# docs/04-istio-cni-and-cilium.md and config/versions.env's
# CILIUM_CNI_CHAINING_REQUIRED_VALUES). This module NEVER modifies
# Cilium itself — this function only detects and reports; remediation
# is a manual step the user runs against
# ../../auto-setup-default-kube-env's existing Cilium release.
cilium_cni_chaining_ready() {
  local current_values
  current_values="$(helm get values cilium -n kube-system 2>/dev/null || true)"
  if [ -z "${current_values}" ]; then
    log_warn "Could not read the live Cilium Helm release's values (helm get values cilium -n kube-system) — cannot confirm CNI-chaining compatibility. Continuing, but see docs/04-istio-cni-and-cilium.md if Istio CNI fails to come up."
    return 1
  fi
  if grep -qE 'exclusive:\s*false' <<<"${current_values}" \
     && grep -qE 'hostNamespaceOnly:\s*true' <<<"${current_values}"; then
    return 0
  fi
  return 1
}

print_cilium_cni_chaining_remediation() {
  cat <<'EOF'
[WARN] The live Cilium installation does not have the values Istio CNI
       chaining requires (cni.exclusive=false, socketLB.hostNamespaceOnly=
       true). This is a known, documented gap between Phase 2's default
       Cilium install and Phase 4's Istio CNI requirement — see
       docs/04-istio-cni-and-cilium.md for the full explanation.

       This module (istio/) never modifies Cilium itself. To remediate,
       run this manually against the EXISTING Cilium release from
       ../auto-setup-default-kube-env (adjust --version to match the
       pinned Cilium chart version in that module's config/versions.env):

         helm upgrade cilium cilium/cilium \
           --namespace kube-system \
           --version <CILIUM_CHART_VERSION from auto-setup-default-kube-env> \
           --reuse-values \
           --set cni.exclusive=false \
           --set socketLB.hostNamespaceOnly=true

       Then re-run 'make verify-cluster' to confirm.
EOF
}

# proxy_status_synced NAME NAMESPACE — checks istioctl proxy-status
# reports a given workload's proxy as fully synced (SYNCED, not STALE).
proxy_status_synced() {
  local pod="$1" namespace="$2" status
  status="$(istioctl proxy-status 2>/dev/null | grep "^${pod}\.${namespace}" || true)"
  [ -n "${status}" ] && ! grep -qi 'STALE' <<<"${status}"
}

istio_revision_installed() {
  kubectl get deployment -n "${ISTIO_SYSTEM_NAMESPACE}" -l "istio.io/rev=${ISTIO_REVISION}" --no-headers 2>/dev/null | grep -q .
}
