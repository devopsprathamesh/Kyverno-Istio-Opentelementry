# Lab 20: Troubleshooting

## Objective

Work through 4 deliberately-introduced failures using `docs/21-troubleshooting.md`'s decision tree and table, practicing the full six-part structure (investigation → root cause → mitigation → fix → validation → prevention) on each.

## Concepts exercised

The complete `docs/21-troubleshooting.md` reference, applied hands-on.

## Prerequisites

Labs 07, 08/09 complete.

## Scenario A: broken Loki OTLP endpoint

1. **Break it**: edit a local copy of `collector/gateway/configmap.yaml`, change `otlphttp/loki.endpoint` to `http://loki.observability.svc.cluster.local:3100/otlp/v1/logs` (the double-appended-path mistake `docs/21-troubleshooting.md` names explicitly), reapply, restart the Gateway.
2. **Investigate**: `bash tests/logs-test.sh` fails; `kubectl -n opentelemetry logs -l app=otel-collector-gateway | grep -i loki` shows 404s.
3. **Root cause**: the exporter's own `/v1/logs` suffix plus the manually-added one in the endpoint.
4. **Fix**: restore the correct endpoint (`.../otlp` only), reapply, restart.
5. **Validate**: `bash tests/logs-test.sh` passes again.

## Scenario B: missing RBAC for k8sattributes

1. **Break it**: `kubectl delete clusterrolebinding otel-collector-agent`.
2. **Investigate**: generate traffic, check whether new telemetry has `k8s.namespace.name` — it won't; check Agent logs for RBAC/forbidden errors.
3. **Root cause**: `k8sattributes` can no longer query the Kubernetes API.
4. **Fix**: `kubectl apply -f collector/agent/clusterrolebinding.yaml`.
5. **Validate**: new telemetry carries Kubernetes metadata again.

## Scenario C: Operator webhook race

1. **Break it**: `kubectl -n opentelemetry scale deployment/opentelemetry-operator --replicas=0`, then immediately `kubectl -n otel-demo rollout restart deployment/frontend`.
2. **Investigate**: `kubectl get pod -n otel-demo -l app=frontend -o jsonpath='{.spec.initContainers}'` — empty, even though the annotation is present.
3. **Root cause**: the webhook wasn't there to intercept pod creation.
4. **Fix**: `kubectl -n opentelemetry scale deployment/opentelemetry-operator --replicas=1`, wait for Ready, then `kubectl -n otel-demo rollout restart deployment/frontend` again.
5. **Validate**: init container now present.

## Scenario D: memory_limiter misconfiguration

1. **Break it**: edit a copy of `collector/gateway/configmap.yaml`, set `memory_limiter.limit_mib` to a value ABOVE the Deployment's `resources.limits.memory` (`collector/gateway/deployment.yaml`), reapply, restart.
2. **Investigate**: drive load (`make generate-load ARGS="300 30 30"`), watch `kubectl -n opentelemetry get pods -l app=otel-collector-gateway -w` for an OOMKill.
3. **Root cause**: no real memory headroom below the container's hard limit.
4. **Fix**: restore `limit_mib` to a value meaningfully below `resources.limits.memory`.
5. **Validate**: repeat the load test, confirm no OOMKill.

## Validation

For each scenario, you produced the failure yourself, diagnosed it using the documented method, and confirmed the fix — not just read about it.

## Cleanup

```bash
kubectl apply -f collector/agent/clusterrolebinding.yaml
kubectl apply -f collector/gateway/clusterrolebinding.yaml
# Restore any locally-edited configmap.yaml copies to their original committed state
kubectl -n opentelemetry rollout restart daemonset/otel-collector-agent deployment/otel-collector-gateway
```

## Reflection

Scenario C's failure (missing init container) produces NO error anywhere — no failed pod, no crash, no log line — it just silently doesn't happen. Contrast this with Scenario B's failure (RBAC missing), which DOES produce visible log errors. What does this difference tell you about which failure modes need proactive monitoring/alerting versus which ones are self-evident from normal troubleshooting?
