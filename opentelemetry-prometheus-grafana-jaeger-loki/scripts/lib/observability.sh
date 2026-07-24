#!/usr/bin/env bash
# Observability-specific helpers: querying Prometheus/Jaeger/Loki/Grafana
# HTTP APIs and parsing Collector internal metrics. Source this file,
# never execute it directly. Assumes common.sh and kubernetes.sh have
# already been sourced. Every function here expects the relevant
# port-forward to already be running on the given local port (see
# scripts/port-forward.sh) — none of these start their own port-forward,
# so callers control setup/teardown and can trap-cleanup correctly.
set -euo pipefail

# prometheus_query LOCAL_PORT PROMQL_EXPRESSION
# Returns the raw JSON response body from Prometheus's instant-query API.
prometheus_query() {
  local port="$1" query="$2"
  curl -fsS -G "http://127.0.0.1:${port}/api/v1/query" --data-urlencode "query=${query}" 2>/dev/null || true
}

# prometheus_query_has_result LOCAL_PORT PROMQL_EXPRESSION
# True if the query returned at least one non-empty result vector.
prometheus_query_has_result() {
  local port="$1" query="$2" body result_count
  body="$(prometheus_query "${port}" "${query}")"
  [ -n "${body}" ] || return 1
  result_count="$(printf '%s' "${body}" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(len(d.get("data", {}).get("result", [])))
except Exception:
    print(0)' 2>/dev/null || echo 0)"
  [ "${result_count}" -gt 0 ]
}

# prometheus_target_healthy LOCAL_PORT JOB_NAME_SUBSTRING
prometheus_target_healthy() {
  local port="$1" job_substring="$2" body
  body="$(curl -fsS "http://127.0.0.1:${port}/api/v1/targets" 2>/dev/null || true)"
  [ -n "${body}" ] || return 1
  printf '%s' "${body}" | python3 -c "
import json,sys
d = json.load(sys.stdin)
active = d.get('data', {}).get('activeTargets', [])
matches = [t for t in active if '${job_substring}' in t.get('labels', {}).get('job', '')]
ok = [t for t in matches if t.get('health') == 'up']
sys.exit(0 if matches and len(ok) == len(matches) else 1)
" 2>/dev/null
}

# jaeger_services LOCAL_PORT
# Returns a newline-separated list of service names Jaeger knows about.
jaeger_services() {
  local port="$1" body
  body="$(curl -fsS "http://127.0.0.1:${port}/api/services" 2>/dev/null || true)"
  [ -n "${body}" ] || return 0
  printf '%s' "${body}" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print("\n".join(d.get("data", []) or []))
except Exception:
    pass' 2>/dev/null || true
}

# jaeger_has_traces_for_service LOCAL_PORT SERVICE_NAME
jaeger_has_traces_for_service() {
  local port="$1" service="$2" body count
  body="$(curl -fsS -G "http://127.0.0.1:${port}/api/traces" --data-urlencode "service=${service}" --data-urlencode "limit=5" 2>/dev/null || true)"
  [ -n "${body}" ] || return 1
  count="$(printf '%s' "${body}" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(len(d.get("data", []) or []))
except Exception:
    print(0)' 2>/dev/null || echo 0)"
  [ "${count}" -gt 0 ]
}

# loki_query_range LOCAL_PORT LOGQL_EXPRESSION
loki_query_range() {
  local port="$1" query="$2"
  curl -fsS -G "http://127.0.0.1:${port}/loki/api/v1/query_range" \
    --data-urlencode "query=${query}" --data-urlencode "limit=5" 2>/dev/null || true
}

# loki_query_has_result LOCAL_PORT LOGQL_EXPRESSION
loki_query_has_result() {
  local port="$1" query="$2" body count
  body="$(loki_query_range "${port}" "${query}")"
  [ -n "${body}" ] || return 1
  count="$(printf '%s' "${body}" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    streams = d.get("data", {}).get("result", [])
    print(sum(len(s.get("values", [])) for s in streams))
except Exception:
    print(0)' 2>/dev/null || echo 0)"
  [ "${count}" -gt 0 ]
}

# grafana_healthy LOCAL_PORT
grafana_healthy() {
  local port="$1" body
  body="$(curl -fsS "http://127.0.0.1:${port}/api/health" 2>/dev/null || true)"
  grep -q '"database"[[:space:]]*:[[:space:]]*"ok"' <<<"${body}"
}

# grafana_datasource_healthy LOCAL_PORT DATASOURCE_UID ADMIN_USER ADMIN_PASS
grafana_datasource_healthy() {
  local port="$1" uid="$2" user="$3" pass="$4" body
  body="$(curl -fsS -u "${user}:${pass}" "http://127.0.0.1:${port}/api/datasources/uid/${uid}/health" 2>/dev/null || true)"
  grep -q '"status"[[:space:]]*:[[:space:]]*"OK"' <<<"${body}"
}

# collector_internal_metric LOCAL_PORT METRIC_NAME_SUBSTRING
# Prints the raw Prometheus-format lines matching the metric name — used
# to read otelcol_receiver_accepted_*, otelcol_exporter_sent_*,
# otelcol_exporter_send_failed_*, otelcol_processor_dropped_* etc. from
# the Collector's own /metrics endpoint (COLLECTOR_INTERNAL_METRICS_PORT).
collector_internal_metric() {
  local port="$1" name_substring="$2"
  curl -fsS "http://127.0.0.1:${port}/metrics" 2>/dev/null | grep "^${name_substring}" || true
}

# collector_health_check LOCAL_PORT
# Reads the health_check extension's endpoint (COLLECTOR_HEALTH_CHECK_PORT).
collector_health_check() {
  local port="$1"
  curl -fsS "http://127.0.0.1:${port}/" 2>/dev/null | grep -qi '"status"[[:space:]]*:[[:space:]]*"Server available"' || \
  curl -fsS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/" 2>/dev/null | grep -q '^200$'
}

# send_test_otlp_trace LOCAL_HTTP_PORT SERVICE_NAME
# POSTs one minimal OTLP/HTTP trace with a single span, protobuf-free
# (OTLP/HTTP JSON encoding), so this works with only curl + python3 — no
# grpcurl or OTel SDK required. Used by the Jaeger-only and Collector-only
# labs to prove ingestion without needing the full demo app running.
send_test_otlp_trace() {
  local port="$1" service_name="$2" trace_id span_id now_ns
  trace_id="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
  span_id="$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
  now_ns="$(date +%s%N)"
  python3 - "$port" "$service_name" "$trace_id" "$span_id" "$now_ns" <<'PYEOF'
import json, sys, urllib.request

port, service_name, trace_id, span_id, now_ns = sys.argv[1:6]
now_ns = int(now_ns)
payload = {
    "resourceSpans": [{
        "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": service_name}}]},
        "scopeSpans": [{
            "spans": [{
                "traceId": trace_id, "spanId": span_id, "name": "manual-test-span",
                "kind": 2, "startTimeUnixNano": str(now_ns), "endTimeUnixNano": str(now_ns + 1_000_000),
                "status": {"code": 1},
            }]
        }]
    }]
}
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/traces",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
urllib.request.urlopen(req, timeout=5).read()
print(trace_id)
PYEOF
}

# send_test_otlp_log LOCAL_HTTP_PORT SERVICE_NAME MESSAGE
send_test_otlp_log() {
  local port="$1" service_name="$2" message="$3" now_ns
  now_ns="$(date +%s%N)"
  python3 - "$port" "$service_name" "$message" "$now_ns" <<'PYEOF'
import json, sys, urllib.request

port, service_name, message, now_ns = sys.argv[1:5]
payload = {
    "resourceLogs": [{
        "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": service_name}}]},
        "scopeLogs": [{
            "logRecords": [{
                "timeUnixNano": now_ns, "severityText": "INFO",
                "body": {"stringValue": message},
            }]
        }]
    }]
}
req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/logs",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
urllib.request.urlopen(req, timeout=5).read()
PYEOF
}
