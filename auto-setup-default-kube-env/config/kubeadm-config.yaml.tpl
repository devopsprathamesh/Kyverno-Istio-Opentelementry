# kubeadm control-plane configuration template, rendered by
# scripts/lib/common.sh::render_template() into
# .generated/rendered/kubeadm-config.yaml before `kubeadm init` runs.
#
# Placeholders (${VAR}) are substituted from config/cluster.env and
# config/versions.env — see docs/ARCHITECTURE.md §3 and
# docs/DECISIONS.md ADR-011 for the reasoning behind the values below,
# in particular why no `podSubnet` is set (Cilium manages pod IPAM).
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  name: ${CONTROL_PLANE_NAME}
  criSocket: ${CRI_SOCKET}
  kubeletExtraArgs:
    - name: "node-ip"
      value: "${CONTROL_PLANE_IP}"
localAPIEndpoint:
  advertiseAddress: ${CONTROL_PLANE_IP}
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: ${CLUSTER_NAME}
kubernetesVersion: v${KUBERNETES_VERSION}
controlPlaneEndpoint: "${CONTROL_PLANE_ENDPOINT}"
networking:
  serviceSubnet: "${SERVICE_SUBNET}"
  # Deliberately no podSubnet: Cilium's cluster-pool IPAM
  # (${CILIUM_CLUSTER_POOL_CIDR}, /${CILIUM_CLUSTER_POOL_MASK_SIZE} per
  # node) manages pod IPs directly and does not consume kube-controller-
  # manager's --allocate-node-cidrs/--cluster-cidr the way Flannel/Calico
  # do. See docs/DECISIONS.md ADR-011.
apiServer:
  certSANs:
    - "${CONTROL_PLANE_IP}"
    - "${CONTROL_PLANE_NAME}"
    - "localhost"
    - "127.0.0.1"
# kube-proxy is retained initially (docs/DECISIONS.md ADR-003); no
# skipKubeProxy option is set here, which keeps kubeadm's default
# kube-proxy install in place.
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
