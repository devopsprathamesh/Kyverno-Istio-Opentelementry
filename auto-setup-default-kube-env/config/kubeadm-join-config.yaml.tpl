# kubeadm JoinConfiguration template for worker nodes, rendered by
# scripts/guest/07-join-worker.sh into
# .generated/rendered/kubeadm-join-config-${NODE_NAME}.yaml.
#
# This is the standard, documented mechanism for pinning a joining
# node's kubelet --node-ip (nodeRegistration.kubeletExtraArgs), mirroring
# InitConfiguration's use of the same field on the control plane in
# config/kubeadm-config.yaml.tpl. Discovery fields are filled in from
# .generated/cluster-info.env, written by 05-init-control-plane.sh.
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
nodeRegistration:
  name: ${NODE_NAME}
  criSocket: ${CRI_SOCKET}
  kubeletExtraArgs:
    - name: "node-ip"
      value: "${NODE_IP}"
discovery:
  bootstrapToken:
    apiServerEndpoint: "${CONTROL_PLANE_ENDPOINT}"
    token: "${KUBEADM_TOKEN}"
    caCertHashes:
      - "${KUBEADM_CA_CERT_HASH}"
