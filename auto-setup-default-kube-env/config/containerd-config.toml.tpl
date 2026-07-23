# containerd 2.x config overlay reference.
#
# containerd 2.0 restructured the CRI plugin into several
# `io.containerd.cri.v1.*` sub-plugins (images/runtime/etc.), replacing
# the single `io.containerd.grpc.v1.cri` plugin from containerd 1.x.
# Hand-authoring a full config.toml against that schema risks drifting
# from whatever the pinned containerd ${CONTAINERD_VERSION} binary
# actually expects.
#
# Instead, scripts/guest/03-install-containerd.sh generates the
# authoritative default config with the installed binary itself
# (`containerd config default`) and then patches only the keys below,
# which is the same pattern the upstream Kubernetes container-runtime
# install guide recommends. This file documents — and is grepped by
# tests/vagrant-validation.sh to confirm — exactly which keys are
# patched and to what value, so the two never drift apart silently.
#
# Required post-generation overrides (applied via sed against whichever
# plugin path the installed containerd version actually emits):
#
#   SystemdCgroup = true
#     Path: the runc runtime options block under the CRI runtime plugin
#     (io.containerd.cri.v1.runtime...runtimes.runc.options in
#     containerd 2.x; io.containerd.grpc.v1.cri...runtimes.runc.options
#     in containerd 1.x — the guest script detects which key exists in
#     the generated default config before patching).
#     Why: kubelet's cgroup driver is pinned to systemd
#     (config/kubeadm-config.yaml.tpl KubeletConfiguration.cgroupDriver)
#     and must match containerd's runc cgroup driver exactly, or kubelet
#     fails to start reliably.
#
#   sandbox_image = "registry.k8s.io/pause:3.10"
#     Path: the CRI images plugin's sandbox_image key.
#     Why: pin the pause container explicitly rather than trust
#     containerd's compiled-in default, per this repository's version-
#     pinning requirement (docs/DECISIONS.md ADR-010).
#
# The rendered, actually-applied config is written to
# .generated/rendered/containerd-config.toml on the control-plane and
# each worker for inspection (not committed — see .gitignore).
