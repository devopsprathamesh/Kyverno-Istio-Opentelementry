#!/usr/bin/env bash
# Runtime check: pod-to-pod (same node + cross node), pod-to-Service,
# DNS, internet egress, API Service connectivity, CiliumNetworkPolicy
# enforcement, and Hubble visibility for allowed/denied flows. Requires
# a live cluster with Cilium ready — skips gracefully (exit 0, reason
# printed) if the cluster isn't reachable. Always cleans up its temporary
# namespace, even on failure.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${MODULE_ROOT}/.generated/kubeconfig"
# shellcheck source=../config/cluster.env
source "${MODULE_ROOT}/config/cluster.env"

if [ ! -f "${KUBECONFIG_PATH}" ]; then
  echo "[INFO] No kubeconfig at ${KUBECONFIG_PATH} — cluster not provisioned. Nothing to test. Run 'make setup' first."
  exit 0
fi
export KUBECONFIG="${KUBECONFIG_PATH}"
if ! kubectl get --raw=/healthz >/dev/null 2>&1; then
  echo "[INFO] API server not reachable — cluster is not currently up. Nothing to test."
  exit 0
fi

NS="network-test"
FAIL=0
cleanup() { kubectl delete namespace "${NS}" --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

run_pod() {
  local name="$1" node="$2"
  kubectl run "${name}" -n "${NS}" --image=nicolaka/netshoot:latest --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"${node}\"}}" -- sleep 3600 >/dev/null
  kubectl -n "${NS}" wait --for=condition=Ready "pod/${name}" --timeout=60s >/dev/null
}

echo "==> Deploying test pods (worker1: pod-a, pod-b; worker2: pod-c)"
run_pod pod-a "${WORKER1_NAME}"
run_pod pod-b "${WORKER1_NAME}"
run_pod pod-c "${WORKER2_NAME}"

POD_A_IP="$(kubectl -n "${NS}" get pod pod-a -o jsonpath='{.status.podIP}')"

check() {
  local description="$1"; shift
  if "$@"; then echo "[PASS] ${description}"; else echo "[FAIL] ${description}"; FAIL=1; fi
}

check "Pod-to-pod, same node (pod-b -> pod-a)" \
  kubectl -n "${NS}" exec pod-b -- sh -c "ping -c2 -W1 ${POD_A_IP}"
check "Pod-to-pod, cross node (pod-c -> pod-a)" \
  kubectl -n "${NS}" exec pod-c -- sh -c "ping -c2 -W1 ${POD_A_IP}"

kubectl -n "${NS}" expose pod pod-a --port=80 --target-port=80 --name=svc-a >/dev/null 2>&1 || true
check "Pod-to-Service (pod-b -> svc-a ClusterIP DNS)" \
  kubectl -n "${NS}" exec pod-b -- sh -c "getent hosts svc-a.${NS}.svc.cluster.local"

check "DNS resolution (kubernetes.default)" \
  kubectl -n "${NS}" exec pod-b -- sh -c "getent hosts kubernetes.default.svc.cluster.local"

check "Internet egress from a pod" \
  kubectl -n "${NS}" exec pod-b -- sh -c "curl -fsS -o /dev/null --max-time 5 https://pkgs.k8s.io"

check "API Service connectivity from a pod" \
  kubectl -n "${NS}" exec pod-b -- sh -c "curl -fsSk -o /dev/null --max-time 5 https://kubernetes.default.svc.cluster.local"

echo "==> CiliumNetworkPolicy enforcement (deny pod-a's ingress, then remove)"
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-ingress-to-pod-a
  namespace: ${NS}
spec:
  endpointSelector:
    matchLabels:
      run: pod-a
  ingress: []
EOF
sleep 3
if kubectl -n "${NS}" exec pod-b -- sh -c "ping -c1 -W1 ${POD_A_IP}" >/dev/null 2>&1; then
  echo "[FAIL] CiliumNetworkPolicy did not block ping to pod-a as expected."
  FAIL=1
else
  echo "[PASS] CiliumNetworkPolicy blocked ping to pod-a as expected."
fi

if vagrant ssh "${CONTROL_PLANE_NAME}" -c "command -v hubble" >/dev/null 2>&1; then
  echo "==> Hubble visibility for the denied flow (best-effort)"
  DROPPED="$(vagrant ssh "${CONTROL_PLANE_NAME}" -c "hubble observe --namespace ${NS} --verdict DROPPED --last 5" 2>/dev/null || true)"
  if [ -n "${DROPPED}" ]; then
    echo "[PASS] Hubble shows at least one DROPPED flow for ${NS}."
  else
    echo "[WARN] Could not confirm a DROPPED flow via Hubble CLI (non-fatal — CiliumNetworkPolicy enforcement itself was already confirmed above)."
  fi
else
  echo "[WARN] Hubble CLI not available on the control plane — skipped Hubble visibility check (non-fatal)."
fi

kubectl delete ciliumnetworkpolicy deny-ingress-to-pod-a -n "${NS}" >/dev/null 2>&1 || true

exit "${FAIL}"
