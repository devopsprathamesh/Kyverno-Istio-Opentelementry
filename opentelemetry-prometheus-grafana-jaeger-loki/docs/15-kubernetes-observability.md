# Kubernetes Observability

## Definition

The specific ways Kubernetes-native metadata and mechanics intersect with this lab's observability pipeline — namespace strategy, RBAC scoping, resource metadata enrichment, and what Kubernetes gives you "for free" versus what this module adds.

## Problem solved

Kubernetes' own tools (`kubectl logs`, `kubectl top`) are pod-scoped and ephemeral — they answer "what is this one pod doing right now," not "what happened across this whole request's path 20 minutes ago." This module's namespace/RBAC/metadata design exists to bridge Kubernetes' pod-centric world into the request-centric world traces/correlated-logs need.

## Traditional implementation

Cluster-wide, unscoped log/metrics collection with minimal Kubernetes-metadata enrichment — logs tagged only with a pod name, no deployment/namespace/environment context, making cross-cutting queries ("all ERROR logs across the whole `otel-demo` namespace, any service") harder than they need to be.

## OpenTelemetry implementation

The `k8sattributes` processor (`collector/agent/configmap.yaml`, `collector/gateway/configmap.yaml`) is the actual bridge — it queries the Kubernetes API (via the ServiceAccount RBAC in `collector/agent/clusterrole.yaml`) to resolve a pod's namespace/deployment/node from either its IP (OTLP connection-based association) or its `k8s.pod.uid` (filelog-derived association, from the log file's own path).

## Internal processing flow

```text
Telemetry arrives (OTLP connection, or filelog record with k8s.pod.uid
  from the file path /var/log/pods/<ns>_<pod>_<uid>/...)
  → k8sattributes processor's pod_association resolves which pod
  → queries the (RBAC-scoped, read-only) Kubernetes API for that pod's metadata
  → attaches k8s.namespace.name, k8s.pod.name, k8s.deployment.name, k8s.node.name
  → downstream: these become Loki labels, trace resource attributes,
    and (via Grafana panel variables) dashboard filters
```

## Kubernetes implementation: namespace strategy

`observability` (Prometheus/Alertmanager/Grafana/Jaeger/Loki), `opentelemetry` (Operator, Collector, `Instrumentation` resources), `otel-demo` (demo app + load generator) — three namespaces, never `kube-system`, each carrying `app.kubernetes.io/part-of: observability-learning-lab` (`config/namespaces.env`). `scripts/clean.sh`/`uninstall-all.sh` refuse to touch anything outside `OWNED_NAMESPACES`.

## Working configuration

`collector/agent/clusterrole.yaml` — the actual, minimal RBAC (`pods`/`namespaces`/`replicasets`, `get`/`list`/`watch` only, no write verbs anywhere) the `k8sattributes` processor needs. Read directly.

## Validation commands

```bash
kubectl auth can-i list pods --as=system:serviceaccount:opentelemetry:otel-collector-agent -A
kubectl auth can-i delete pods --as=system:serviceaccount:opentelemetry:otel-collector-agent -A   # expect 'no'
```

## What Kubernetes gives you without this module at all

`kubectl logs`, `kubectl top pod`, `kubectl describe pod` (events, resource requests/limits, restart count), liveness/readiness probe status — all genuinely useful, all pod-scoped and point-in-time, none correlatable across services or retained once the pod is gone.

## What this module adds

Persistent, queryable, cross-service-correlatable telemetry with Kubernetes metadata attached automatically — the `kube-state-metrics`/`node-exporter` metrics (`11-prometheus-architecture.md`) extend this further into cluster-wide workload health (`grafana/dashboards/kubernetes-workload-overview.json`) without needing to poll every pod individually.

## Failure modes

- Missing `k8s.namespace.name`/`k8s.pod.name` on telemetry — usually a `pod_association` misconfiguration or the ServiceAccount RBAC being too narrow; `21-troubleshooting.md` "Kubernetes metadata missing."
- Assuming the Collector's RBAC needs write access to anything — it never does; if a real cluster's RBAC review flags this module for excessive permissions, that's worth investigating as a genuine deviation from `collector/agent/clusterrole.yaml`'s intended least-privilege shape.

## Production considerations

At real cluster scale, `k8sattributes`' Kubernetes API watch load (one watch stream per Collector Agent pod, i.e., per node) is a real, bounded but non-zero load on the API server — worth monitoring alongside the API server's own health in a large cluster, `18-performance-and-capacity.md`.

## Interview-level explanation

*"How does telemetry end up tagged with the right namespace/pod/deployment automatically?"* — The `k8sattributes` processor, running with narrowly-scoped read-only RBAC, resolves each piece of telemetry back to its originating pod (via the OTLP connection's source IP for direct traffic, or via the log file's own path-encoded pod UID for filelog-derived logs) and queries the Kubernetes API for that pod's current metadata, attaching it as resource attributes. This happens automatically for every service in this lab, auto- or manually-instrumented alike — it's a Collector-pipeline concern, not something each application has to implement itself.
