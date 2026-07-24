# Lab 02: Prometheus Only

## Objective

Install and query Prometheus in complete isolation — no Grafana, no Collector, no demo app required.

## Concepts exercised

Pull-based scraping, `ServiceMonitor`/`PodMonitor`, PromQL, recording/alerting rules (`docs/11-prometheus-architecture.md`).

## Prerequisites

Lab 00 complete.

## Steps

1. **Install only Prometheus**:
   ```bash
   make install-operator     # Prometheus Operator's CRDs come from kube-prometheus-stack itself, not the OTel Operator — this step is NOT required for this lab; skip it
   make install-prometheus LAB_PROFILE=minimum
   make validate-prometheus
   ```
   (The `install-operator` line above is a deliberate red herring to notice — Prometheus's own Operator CRDs come bundled with `install-prometheus`'s `kube-prometheus-stack` chart; the OpenTelemetry Operator is unrelated and not needed for this lab.)

2. **Query directly, without Grafana**:
   ```bash
   make port-forward-prometheus &
   curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
   ```

3. **Check what targets exist** (kube-state-metrics/node-exporter are already being scraped, even with nothing else installed):
   ```bash
   curl -s http://localhost:9090/api/v1/targets | python3 -c "import json,sys; d=json.load(sys.stdin); print([t['labels']['job'] for t in d['data']['activeTargets']])"
   ```

4. **Run PromQL examples directly** from `prometheus/queries/promql-examples.md`'s "Kubernetes workload" section (the only section that works with nothing else installed):
   ```bash
   curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace)' | python3 -m json.tool
   ```

5. **Confirm recording/alerting rules are loaded** even with no application metrics flowing yet:
   ```bash
   curl -s http://localhost:9090/api/v1/rules | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['data']['groups']))"
   ```

## Validation

```bash
bash tests/prometheus-test.sh
```

## Failure scenarios to notice

Query `orders_total` (a demo-app metric) — expect no results, since neither the Collector nor the demo app is installed yet in this lab. This is the expected, correct behavior — confirms Prometheus itself works completely independently of everything else in this module.

## Cleanup

```bash
# Ctrl-C the port-forward
make uninstall-prometheus
```

## Reflection

Prometheus was able to scrape kube-state-metrics/node-exporter targets before you installed anything else in this module. What does that tell you about which of this lab's telemetry sources are Kubernetes-native (always available) versus which depend on this module's own pipeline (`docs/DECISIONS.md` ADR-025)?
