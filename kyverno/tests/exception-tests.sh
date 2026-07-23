#!/usr/bin/env bash
# Runtime test: PolicyException applies ONLY to its named target, not to
# any other resource matching the same underlying pattern.
set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "${MODULE_ROOT}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/kubernetes.sh
source "${MODULE_ROOT}/scripts/lib/kubernetes.sh"

if ! kube_reachable; then
  log_info "No reachable cluster — exception-tests skipped."
  exit 0
fi

FAIL=0
cleanup() {
  kubectl -n "${DEMO_NAMESPACE}" delete pod demo-approved-hostpath-reader unapproved-hostpath-reader --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f "${MODULE_ROOT}/policies/exceptions/allow-demo-hostpath-exception.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -f "${MODULE_ROOT}/policies/validate/restrict-privileged-containers.yaml" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

log_section "exception-tests"
kubectl apply -f "${MODULE_ROOT}/demo/namespace.yaml" >/dev/null
kubectl apply -f "${MODULE_ROOT}/policies/validate/restrict-privileged-containers.yaml" >/dev/null
kubectl apply -f "${MODULE_ROOT}/policies/exceptions/allow-demo-hostpath-exception.yaml" >/dev/null
wait_for "restrict-privileged-containers Ready" 60 3 -- \
  bash -c "kubectl get clusterpolicy restrict-privileged-containers -o jsonpath='{.status.ready}' | grep -qx true"

# The exempted, by-name resource: should be admitted despite hostPath.
if kubectl apply -f "${MODULE_ROOT}/demo/test-resources/demo-approved-hostpath-reader.yaml" >/dev/null 2>&1; then
  log_pass "Exempted resource 'demo-approved-hostpath-reader' was admitted despite the hostPath rule."
else
  log_fail "Exempted resource was rejected — PolicyException did not apply as expected."
  FAIL=1
fi

# A DIFFERENTLY-NAMED Pod with the same hostPath pattern: should still be rejected.
cat <<EOF >/tmp/unapproved-hostpath-reader.$$.yaml
apiVersion: v1
kind: Pod
metadata:
  name: unapproved-hostpath-reader
  namespace: ${DEMO_NAMESPACE}
  labels: {lab-marker: intentionally-insecure}
spec:
  containers:
    - name: app
      image: registry.k8s.io/pause:3.10
      resources: {requests: {cpu: 10m, memory: 16Mi}, limits: {memory: 32Mi}}
      volumeMounts: [{name: host-tmp, mountPath: /host-tmp, readOnly: true}]
  volumes: [{name: host-tmp, hostPath: {path: /tmp, type: Directory}}]
EOF
if kubectl apply -f "/tmp/unapproved-hostpath-reader.$$.yaml" >/dev/null 2>&1; then
  log_fail "A differently-named Pod with the same hostPath pattern was admitted — the exception is not scoped narrowly enough."
  FAIL=1
else
  log_pass "A differently-named Pod with the same hostPath pattern was correctly still rejected — the exception is scoped to exactly one resource name."
fi
rm -f "/tmp/unapproved-hostpath-reader.$$.yaml"

exit "${FAIL}"
