# Cilium Helm values template, rendered by 06-install-cilium.sh into
# .generated/rendered/cilium-values.yaml. A values file (per
# docs/REPOSITORY-GOVERNANCE.md "one values file per profile, not inline
# --set flags") rather than a long --set chain, so the actually-applied
# configuration is reviewable here in git.
#
# kube-proxy is retained initially (docs/DECISIONS.md ADR-003) — Cilium
# runs in "disabled" kube-proxy-replacement mode (i.e. Cilium does not
# replace kube-proxy) and coexists with it. Pod IPAM uses Cilium's own
# cluster-pool allocator rather than a kubeadm-provided podSubnet
# (docs/DECISIONS.md ADR-011).
#
# HUBBLE_UI_ENABLED is set by 06-install-cilium.sh (default "true";
# override via the HUBBLE_UI_ENABLED env var — see .env.example).

kubeProxyReplacement: disabled

k8sServiceHost: "${CONTROL_PLANE_IP}"
k8sServicePort: 6443

ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList:
      - "${CILIUM_CLUSTER_POOL_CIDR}"
    clusterPoolIPv4MaskSize: ${CILIUM_CLUSTER_POOL_MASK_SIZE}

operator:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
  prometheus:
    enabled: true

# Metrics endpoints are exposed for future Prometheus scraping
# (docs/DEPENDENCIES.md §10) but no Prometheus server is installed here —
# that would violate this module's tool-neutral scope.
prometheus:
  enabled: true

resources:
  requests:
    cpu: 100m
    memory: 256Mi

hubble:
  enabled: true
  relay:
    enabled: true
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
  ui:
    enabled: ${HUBBLE_UI_ENABLED}
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
