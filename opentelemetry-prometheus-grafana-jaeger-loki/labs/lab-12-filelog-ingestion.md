# Lab 12: Filelog Ingestion

## Objective

Trace one log line's complete path from container stdout to a queryable Loki record, verifying every stage of `collector/agent/configmap.yaml`'s pipeline directly.

## Concepts exercised

`docs/06-logs.md`'s full filelog pipeline, CRI parsing, multiline recombination, checkpointing.

## Prerequisites

Lab 07 complete (Collector installed), demo app deployed (lab 08/09).

## Steps

1. **Confirm the raw log file exists on the node** (via a debug pod, since you likely don't have direct node SSH access from this environment):
   ```bash
   NODE=$(kubectl get pod -n otel-demo -l app=order-service -o jsonpath='{.items[0].spec.nodeName}')
   kubectl debug node/"${NODE}" -it --image=busybox -- chroot /host sh -c 'ls /var/log/pods/ | grep otel-demo_order-service'
   ```

2. **Generate a log line and find it at each pipeline stage**:
   ```bash
   kubectl -n otel-demo exec deploy/frontend -- curl -s -X POST http://localhost:3000/
   kubectl -n otel-demo logs -l app=order-service --tail=5   # stage 1: raw container stdout
   ```

3. **Confirm the Agent actually read it**:
   ```bash
   kubectl -n opentelemetry logs -l app=otel-collector-agent --tail=20 | grep -i order-service
   ```
   (If Agent logging is quiet by default, check `otelcol_receiver_accepted_log_records` instead — step 5.)

4. **Confirm it reached Loki, with Kubernetes metadata attached**:
   ```bash
   make port-forward-loki &
   curl -s -G http://localhost:3100/loki/api/v1/query_range \
     --data-urlencode 'query={k8s_namespace_name="otel-demo", service_name="order-service"}' \
     --data-urlencode 'limit=5' | python3 -m json.tool
   ```

5. **Confirm the Agent's own metrics show non-zero log-record acceptance**:
   ```bash
   kubectl -n opentelemetry port-forward daemonset/otel-collector-agent 8888:8888 &
   curl -s http://localhost:8888/metrics | grep otelcol_receiver_accepted_log_records
   ```

## Validation

```bash
bash tests/logs-test.sh
```

## Failure scenarios to notice

Delete the Agent pod on the node running `order-service` (`kubectl -n opentelemetry delete pod -l app=otel-collector-agent --field-selector spec.nodeName=<node>`), generate more traffic while it's restarting, then once it's back, confirm via `kubectl -n opentelemetry exec` (or a debug pod) that `/var/lib/otelcol-agent-checkpoint` (the hostPath checkpoint volume) still has recent modification timestamps — direct evidence the checkpoint survived the pod restart, per `docs/06-logs.md`'s duplication-avoidance design.

## Cleanup

None beyond the debug pod from step 1, if still running (`kubectl debug` sessions clean up automatically on exit).

## Reflection

Step 1 found the raw log file at a path derived from namespace_pod_uid. Given `collector/agent/configmap.yaml`'s `exclude` pattern (`/var/log/pods/opentelemetry_otel-collector-agent-*/*/*.log`), explain precisely why that specific exclusion exists and what would happen without it.
