# Dashboards Used in This Lab

All 5 dashboards are provisioned automatically by `make install-grafana` from [`../../grafana/dashboards/`](../../grafana/dashboards/) — not duplicated here. This capstone's [`../scenarios/incident-workflow.md`](../scenarios/incident-workflow.md) uses them in this order:

1. **Application Overview** (`application-overview.json`) — where the incident is first noticed (error rate / P95 latency spike).
2. **Service Performance** (`service-performance.json`) — narrows down to which specific service.
3. **OpenTelemetry Collector Health** (`collector-health.json`) — rules out (or confirms) a pipeline-level problem versus an application-level one.
4. **Logs** (`logs.json`) — the correlated-logs step of the incident workflow.
5. **Kubernetes Workload Overview** (`kubernetes-workload-overview.json`) — confirms whether the root cause has an infrastructure component (restarts, resource pressure) alongside the application-level one.

See [`../../docs/12-grafana-architecture.md`](../../docs/12-grafana-architecture.md) for how provisioning works, and [`../../grafana/correlations/README.md`](../../grafana/correlations/README.md) for the cross-dashboard navigation (exemplars, trace-to-log links) this workflow depends on.
