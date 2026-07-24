# Rules

Recording rules live in [`../recording-rules/`](../recording-rules/); alerting rules live in [`../alerts/`](../alerts/) — split into two directories rather than one so each `PrometheusRule` object has a single, obvious responsibility (compute a reusable series vs. fire an alert), matching how `scripts/install-prometheus.sh` applies them as two separate `kubectl apply -f` steps. See [`../../docs/11-prometheus-architecture.md`](../../docs/11-prometheus-architecture.md) "Recording rules and alerting rules".
