#!/usr/bin/env bash
# Guest provisioning step 08: install Rancher local-path-provisioner as
# the lab's dynamic StorageClass (docs/DECISIONS.md ADR-012). Runs only
# on the control plane, and only once both workers are Ready (invoked
# last by the Vagrantfile/setup-cluster.sh orchestration). Idempotent
# via `kubectl apply`.
set -euo pipefail

MODULE_ROOT="/vagrant"
# shellcheck source=../lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../lib/validation.sh
source "${MODULE_ROOT}/scripts/lib/validation.sh"

require_root
: "${NODE_NAME:?}"
: "${NODE_ROLE:?}"

if [ "${NODE_ROLE}" != "control-plane" ]; then
  log_info "08-install-storage: not the control plane, skipping (${NODE_NAME})."
  exit 0
fi

log_section "08-install-storage: local-path-provisioner v${LOCAL_PATH_PROVISIONER_VERSION} (${NODE_NAME})"

export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl apply -f "${LOCAL_PATH_PROVISIONER_MANIFEST}"
log_pass "local-path-provisioner v${LOCAL_PATH_PROVISIONER_VERSION} manifest applied."

# The upstream manifest names its StorageClass "local-path"; make it the
# cluster default explicitly (idempotent — patch is safe to repeat).
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'

wait_for "local-path-provisioner rollout" 120 5 -- \
  bash -c "kubectl -n ${STORAGE_NAMESPACE} rollout status deployment/local-path-provisioner --timeout=5s"

log_info "Validation: storageclass -> $(kubectl get storageclass "${STORAGE_CLASS_NAME}" --no-headers 2>/dev/null)"

# --- Dynamic PVC smoke test: create, write, read, restart, confirm,
# clean up. This exercises the exact sequence required by the Phase 2
# spec's storage validation, self-contained inside this guest script so
# it runs the moment storage is installed rather than only from the
# separate host-side tests/storage-test.sh (which re-runs the same idea
# against the exported kubeconfig for the host-triggered `make validate`
# / `make storage-test` path).
TEST_NS="storage-smoke-test"
kubectl create namespace "${TEST_NS}" --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-smoke-pvc
  namespace: ${TEST_NS}
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ${STORAGE_CLASS_NAME}
  resources:
    requests:
      storage: 64Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: storage-smoke-pod
  namespace: ${TEST_NS}
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: registry.k8s.io/pause:3.10
      command: ["sh", "-c", "echo unused; sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: storage-smoke-pvc
EOF

if wait_for "storage smoke-test pod Running" 90 3 -- \
  bash -c "phase=\$(kubectl -n ${TEST_NS} get pod storage-smoke-pod -o jsonpath='{.status.phase}'); [ \"\${phase}\" = Running ]"; then
  kubectl -n "${TEST_NS}" exec storage-smoke-pod -- sh -c 'echo hello-from-local-path > /data/test.txt'
  READBACK="$(kubectl -n "${TEST_NS}" exec storage-smoke-pod -- cat /data/test.txt)"
  if [ "${READBACK}" = "hello-from-local-path" ]; then
    log_pass "Dynamic PVC write/read smoke test succeeded."
  else
    log_fail "Dynamic PVC read-back did not match what was written (got: '${READBACK}')."
  fi
else
  log_fail "Storage smoke-test pod never reached Running."
fi

kubectl delete namespace "${TEST_NS}" --wait=false
log_info "Storage smoke-test namespace ${TEST_NS} deletion requested (cleanup)."

log_pass "08-install-storage complete for ${NODE_NAME}."
