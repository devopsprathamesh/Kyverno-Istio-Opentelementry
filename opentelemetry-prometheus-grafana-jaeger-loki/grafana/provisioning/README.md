# Provisioning

Dashboard provisioning is handled by the Grafana Helm chart's built-in sidecar (`sidecar.dashboards.enabled: true` in [`../../install/grafana/values-minimum.yaml`](../../install/grafana/values-minimum.yaml)/[`values-recommended.yaml`](../../install/grafana/values-recommended.yaml)), which watches for any `ConfigMap` labeled `grafana_dashboard=1` in the cluster — `scripts/install-grafana.sh` creates exactly one such `ConfigMap` from every file in [`../dashboards/`](../dashboards/). No separate provisioning YAML is hand-written for dashboards; the sidecar pattern is the provisioning mechanism.

Datasource provisioning works differently (the chart's native `datasources:` values key, not the sidecar) — see [`../datasources/README.md`](../datasources/README.md).
