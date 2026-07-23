#!/usr/bin/env bash
# Runtime check: create PVC -> create pod mounting it -> write data ->
# read data -> restart the pod -> confirm persistence -> clean up.
# Requires a live cluster with the storage provisioner installed; skips
# gracefully (exit 0, reason printed) if the cluster isn't reachable.
# Always cleans up its temporary namespace, even on failure.
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

NS="storage-test"
FAIL=0
cleanup() { kubectl delete namespace "${NS}" --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "==> 1. Create PVC"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-test-pvc
  namespace: ${NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${STORAGE_CLASS_NAME}
  resources:
    requests:
      storage: 64Mi
EOF

echo "==> 2. Create pod mounting the PVC"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod
  namespace: ${NS}
spec:
  restartPolicy: Never
  containers:
    - name: holder
      image: registry.k8s.io/pause:3.10
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: storage-test-pvc
EOF

if ! kubectl -n "${NS}" wait --for=condition=Ready pod/storage-test-pod --timeout=90s >/dev/null 2>&1; then
  echo "[FAIL] storage-test-pod did not reach Ready — dynamic provisioning likely failed."
  kubectl -n "${NS}" get pvc storage-test-pvc -o wide || true
  kubectl -n "${NS}" describe pod storage-test-pod || true
  exit 1
fi
echo "[PASS] PVC bound and pod mounting it reached Ready."

echo "==> 3. Write test data"
kubectl -n "${NS}" exec storage-test-pod -- sh -c "echo persisted-data-$(date +%s) > /data/test.txt"

echo "==> 4. Read test data back"
WRITTEN="$(kubectl -n "${NS}" exec storage-test-pod -- cat /data/test.txt)"
echo "[PASS] Read back: ${WRITTEN}"

echo "==> 5. Restart the pod"
kubectl -n "${NS}" delete pod storage-test-pod --wait=true >/dev/null
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: storage-test-pod
  namespace: ${NS}
spec:
  restartPolicy: Never
  containers:
    - name: holder
      image: registry.k8s.io/pause:3.10
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: storage-test-pvc
EOF
kubectl -n "${NS}" wait --for=condition=Ready pod/storage-test-pod --timeout=90s >/dev/null

echo "==> 6. Confirm data persistence after restart"
READBACK="$(kubectl -n "${NS}" exec storage-test-pod -- cat /data/test.txt)"
if [ "${READBACK}" = "${WRITTEN}" ]; then
  echo "[PASS] Data persisted across pod restart: '${READBACK}'"
else
  echo "[FAIL] Data did NOT persist across restart. Before: '${WRITTEN}' After: '${READBACK}'"
  FAIL=1
fi

echo "==> 7. Clean up test resources"
kubectl delete namespace "${NS}" --wait=false >/dev/null 2>&1 || true
echo "[INFO] Namespace ${NS} deletion requested."

exit "${FAIL}"
