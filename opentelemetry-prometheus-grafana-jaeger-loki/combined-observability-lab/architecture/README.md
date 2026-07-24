# Combined Architecture

This is the complete topology every independent lab (`../../labs/`) builds toward — every component installed together, wired exactly as `make install-all`/`make deploy-demo` configures it.

## Final combined observability architecture

```mermaid
flowchart TB
    subgraph DEMO["otel-demo namespace"]
        LOADGEN["load-generator\n(scripts/generate-load.sh)"]
        FE["frontend (Node.js, auto-instrumented)"]
        OS["order-service (Python, manual)"]
        IS["inventory-service (Python, auto-instrumented)"]
        PS["payment-service (Python, manual,\nconfigurable latency/failure)"]
        LOADGEN --> FE --> OS
        OS --> IS
        OS --> PS
    end

    subgraph OTEL["opentelemetry namespace"]
        OPERATOR["OpenTelemetry Operator\n(webhook injects auto-instrumentation\ninto frontend + inventory-service)"]
        AGENT["Collector Agent DaemonSet\n(filelog: every pod's stdout)"]
        GATEWAY["Collector Gateway Deployment\n(k8sattributes, redaction,\ntail_sampling, batch)"]
    end

    subgraph OBS["observability namespace"]
        PROM["Prometheus\n(kube-prometheus-stack)"]
        ALERTMGR["Alertmanager"]
        JAEGER["Jaeger v2\n(native OTLP)"]
        LOKI["Loki\n(native OTLP)"]
        GRAFANA["Grafana\n(datasources + 5 dashboards,\ncorrelation configured)"]
    end

    OPERATOR -.->|"mutates pod spec\nat creation"| FE
    OPERATOR -.->|"mutates pod spec\nat creation"| IS

    FE & OS & IS & PS -->|"OTLP traces + metrics"| GATEWAY
    DEMO -.->|"container stdout"| AGENT
    AGENT -->|"OTLP logs"| GATEWAY

    GATEWAY -->|"prometheus exporter\n(scrape)"| PROM
    GATEWAY -->|"otlp exporter"| JAEGER
    GATEWAY -->|"otlphttp exporter"| LOKI

    PROM --> ALERTMGR
    PROM & JAEGER & LOKI --> GRAFANA
```

## What's deliberately NOT in this diagram

Kyverno, Istio, and anything from `../../../all-tools-integrated-lab/` — this module is independent, per this phase's explicit scope boundary (`../../docs/DECISIONS.md`, root `PROJECT-IMPLEMENTATION-PLAN.md` Phase 5). The all-tools integration is Phase 6's job, not this one's.

## Reading this diagram against the independent labs

Every arrow here was individually exercised, in isolation, by a specific earlier lab: `frontend`/`inventory-service`'s auto-instrumentation (`../../labs/lab-08-auto-instrumentation.md`), `order-service`/`payment-service`'s manual instrumentation (`lab-09`), the Agent's filelog path (`lab-12`), the Gateway's tail sampling (`lab-15`), and every backend independently (`lab-02` through `lab-05`). This combined lab is where they all run simultaneously for the first time.
