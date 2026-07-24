# Grafana Architecture

## Definition

Grafana is a **visualization layer** — it queries other systems' data (Prometheus, Jaeger, Loki, via **data sources**) and renders **dashboards**, but stores none of the underlying telemetry itself. Restated from `06-logs.md`, worth repeating here as this doc's own central point: **Grafana visualizes; it does not store.**

## Problem solved

Without a unifying visualization layer, an operator investigating an incident would need three separate UIs open, each with its own query language, its own time-range picker, no shared context — Grafana's value is entirely in unifying access and enabling correlation (`08-telemetry-correlation.md`), not in doing anything to the underlying data.

## Traditional implementation

Vendor-specific dashboards bundled with each individual tool (Prometheus's own basic expression browser, Jaeger's own UI, Loki's own minimal UI) — each functional standalone, none correlatable with the others.

## OpenTelemetry implementation

Not directly OTel-specific — Grafana predates and is independent of OpenTelemetry. Its relevance here is entirely as this lab's chosen visualization layer for OTel-originated telemetry that has already reached Prometheus/Jaeger/Loki.

## Internal processing flow

```text
User opens a dashboard panel
  → Grafana's backend issues a query to the relevant datasource's API
    (PromQL to Prometheus, an API call to Jaeger, LogQL to Loki)
  → datasource responds with raw data
  → Grafana renders it client-side
```
No telemetry ever passes through or is retained by Grafana itself beyond the current browser session's rendered view.

## Kubernetes implementation

`install/grafana/values-*.yaml` (`sidecar.dashboards.enabled: true`) — Grafana's own sidecar container watches for `ConfigMap`s labeled `grafana_dashboard=1` in its namespace and loads them automatically; `scripts/install-grafana.sh` creates exactly one such `ConfigMap` from every file in `grafana/dashboards/`.

## Working configuration

`install/grafana/datasources/datasources.yaml` — three data sources, each with correlation config (`08-telemetry-correlation.md`). `grafana/dashboards/*.json` — five provisioned dashboards.

## Validation commands

```bash
make port-forward-grafana &
curl -s -u admin:$(cat .generated/grafana-admin-password) http://localhost:3000/api/datasources | python3 -m json.tool
curl -s -u admin:$(cat .generated/grafana-admin-password) http://localhost:3000/api/search?type=dash-db | python3 -m json.tool
```

## Data sources, dashboard provisioning, folders

A **data source** is a configured connection (URL, auth, correlation settings) to one backend — this lab's three (`prometheus`, `jaeger`, `loki` UIDs, matching `install/grafana/datasources/datasources.yaml`). **Dashboard provisioning** in this lab is entirely sidecar/ConfigMap-based (no separate provisioning YAML — `grafana/provisioning/README.md`). **Folder provisioning** (organizing dashboards into named folders) is not configured in this lab — all 5 dashboards land in Grafana's default/General folder, a documented simplification for a 5-dashboard lab, not a real limitation worth solving here.

## Panels, transformations, dashboard variables, Explore

A **panel** is one visualization (timeseries, stat, table, logs, gauge — all used across `grafana/dashboards/*.json`). **Transformations** reshape query results before rendering (not used in this lab's dashboards — kept simple deliberately). **Dashboard variables** (`grafana/dashboards/service-performance.json`'s `$service` templating variable) let one dashboard serve many filtered views without duplicating panels. **Explore** is Grafana's ad-hoc, dashboard-free query interface — the tool of choice for the kind of unanticipated investigation `01-observability-fundamentals.md` frames as observability's whole point.

## Alerts and contact points, conceptually

Grafana itself has an alerting engine (distinct from Prometheus/Alertmanager's) — this lab does **not** use it; all alerting is Prometheus-rule-based (`prometheus/alerts/`), routed through Alertmanager (bundled by kube-prometheus-stack). Grafana-native alerting and contact points are mentioned here only conceptually, as a real alternative this lab didn't choose, to avoid maintaining two separate alerting systems for one lab.

## Data-source health, authentication

Each data source's `/health` check (`grafana_datasource_healthy` in `scripts/lib/observability.sh`) confirms Grafana can actually reach and authenticate to the backend — a real, useful pre-flight check distinct from "the datasource config exists." Authentication in this lab is basic auth with a randomly-generated admin password (`scripts/install-grafana.sh`, `.generated/grafana-admin-password`, git-ignored, never committed) — `17-security-and-governance.md` covers the production alternative (SSO/OAuth).

## Failure modes

- A dashboard showing "No data" — check the datasource's own health first (`21-troubleshooting.md` "Grafana data source unhealthy" / "Dashboard shows no data"), before assuming the dashboard's query itself is wrong.
- Assuming Grafana retains historical data across a Prometheus/Loki data loss event — it doesn't; Grafana has nothing to show once the underlying backend's data is gone, regardless of how recently it was viewed.

## Production considerations

`16-production-design.md` "Grafana" covers HA (Grafana itself needs a shared database backend for HA, not the default SQLite this lab implicitly uses), backup, and dashboard-as-code recovery — this lab's dashboards already live as JSON in Git (`grafana/dashboards/`), which is itself the production-recommended recovery pattern, just not yet paired with a HA Grafana deployment.

## Interview-level explanation

*"If Grafana went down entirely, what would you lose?"* — Nothing telemetry-wise — Prometheus/Jaeger/Loki keep collecting and storing independently; you'd just lose the visualization/correlation UI until Grafana comes back. This is precisely because Grafana stores nothing itself — it's a stateless (aside from its own small config database) query-and-render layer. The one thing you *would* lose if you also lost the dashboard JSON without it being in Git is the specific panel/query definitions — which is exactly why this lab keeps `grafana/dashboards/*.json` checked in and provisioned automatically on every install, not hand-configured through the UI.
