# opentelemetry-collector Helm chart (documented, NOT what `make install-collector` applies)

This module deploys the Collector agent (DaemonSet) and gateway (Deployment) as **raw Kubernetes manifests** under `../../collector/agent/` and `../../collector/gateway/`, applied by `scripts/install-collector.sh` — not this Helm chart, and not the Operator's `OpenTelemetryCollector` CRD. See root `docs/DECISIONS.md` ADR-029 for the full reasoning: raw manifests give full, explicit control over the agent's hostPath mounts (`/var/log/pods`), RBAC (`k8sattributes` needs pod/namespace read access), and the specific two-tier agent+gateway topology this lab teaches.

## Why documented here at all

`config/versions.env` still pins the chart version (`OTEL_COLLECTOR_HELM_CHART_VERSION`) because:

1. It's a legitimate, commonly-used alternative deployment path worth knowing about — `docs/10-collector-deployment-patterns.md` compares all three (Helm chart, raw manifests, Operator CRD) explicitly.
2. The chart's own `values.yaml` schema was cross-referenced while designing `../../collector/agent/configmap.yaml` and `../../collector/gateway/configmap.yaml`, to make sure this lab's hand-written pipeline configuration matches what a chart-based install would actually produce.

## If you want the Helm chart path instead

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update open-telemetry
helm upgrade --install otel-collector-agent open-telemetry/opentelemetry-collector \
  --namespace opentelemetry \
  --version 0.165.0 \
  --set image.repository=otel/opentelemetry-collector-contrib \
  --set image.tag=0.157.0 \
  --set mode=daemonset \
  -f <your-own-values-file>
```

Not scripted by this module — this lab's own install path is the raw-manifest one described above.
