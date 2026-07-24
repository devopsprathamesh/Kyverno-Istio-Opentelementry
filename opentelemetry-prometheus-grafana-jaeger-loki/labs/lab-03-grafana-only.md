# Lab 03: Grafana Only

## Objective

Install Grafana and confirm the minimal dependency chain it actually needs — at least one working datasource — since Grafana alone has nothing to visualize.

## Concepts exercised

Grafana as a stateless visualization layer (`docs/12-grafana-architecture.md`), datasource provisioning, dashboard sidecar provisioning.

## Prerequisites

Lab 02 complete (Prometheus installed — Grafana's minimal viable dependency for this lab).

## Steps

1. **Install Grafana**:
   ```bash
   make install-grafana LAB_PROFILE=minimum
   make validate-grafana
   ```

2. **Retrieve the generated admin password**:
   ```bash
   cat .generated/grafana-admin-password
   ```
   Note: never committed to Git — `.generated/` is git-ignored (root `.gitignore`).

3. **Log in and check datasource health**:
   ```bash
   make port-forward-grafana &
   ```
   Open `http://localhost:3000`, log in as `admin`/`<the password above>`. Navigate to Connections → Data sources — `prometheus` should show healthy; `jaeger`/`loki` will show unhealthy (not installed yet in this lab) — expected.

4. **Confirm dashboards are provisioned even with two datasources unhealthy**:
   ```bash
   curl -s -u "admin:$(cat .generated/grafana-admin-password)" http://localhost:3000/api/search?type=dash-db | python3 -m json.tool
   ```
   All 5 dashboards should be listed — provisioning doesn't depend on the datasources being healthy, only on the ConfigMap sidecar pattern working (`grafana/provisioning/README.md`).

5. **Open the Kubernetes Workload Overview dashboard** — it should show real data, since it only depends on Prometheus (already installed and healthy).

## Validation

```bash
bash tests/grafana-test.sh
```
Expect the `prometheus` datasource check to pass and `jaeger`/`loki` to fail — matching this lab's intentionally-partial install.

## Failure scenarios to notice

Open the "Logs" dashboard (depends on Loki, not installed) and the "Application Overview" dashboard (depends on demo-app metrics, not deployed) — both show "No data" or a datasource error, a direct, hands-on demonstration of `docs/21-troubleshooting.md`'s "Dashboard shows no data" row and exactly why checking datasource health *first* matters before assuming a panel's query is wrong.

## Cleanup

Leave Grafana and Prometheus installed for later labs, or:
```bash
make uninstall-grafana
```

## Reflection

`docs/12-grafana-architecture.md` states Grafana stores nothing. Given that, if Grafana's pod were deleted and recreated right now, what would be immediately available again, and what (if anything) would be genuinely lost?
