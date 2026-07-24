#!/usr/bin/env python3
"""Minimal, dependency-free OTLP/HTTP client — no OpenTelemetry SDK
involved at all, so you can see exactly what a trace or log payload
looks like on the wire. See README.md for usage and rationale.
"""
import argparse
import json
import secrets
import sys
import time
import urllib.request


def send_trace(endpoint: str, service: str) -> str:
    trace_id = secrets.token_hex(16)
    span_id = secrets.token_hex(8)
    now_ns = time.time_ns()
    payload = {
        "resourceSpans": [{
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": service}},
                ]
            },
            "scopeSpans": [{
                "scope": {"name": "examples/otlp-client"},
                "spans": [{
                    "traceId": trace_id,
                    "spanId": span_id,
                    "name": "raw-otlp-example-span",
                    "kind": 1,  # SPAN_KIND_INTERNAL
                    "startTimeUnixNano": str(now_ns),
                    "endTimeUnixNano": str(now_ns + 2_000_000),
                    "attributes": [
                        {"key": "example.source", "value": {"stringValue": "examples/otlp-client/send-raw-otlp.py"}},
                    ],
                    "status": {"code": 1},  # STATUS_CODE_OK
                }],
            }],
        }]
    }
    _post(f"{endpoint}/v1/traces", payload)
    return trace_id


def send_log(endpoint: str, service: str, message: str) -> None:
    payload = {
        "resourceLogs": [{
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": service}},
                ]
            },
            "scopeLogs": [{
                "scope": {"name": "examples/otlp-client"},
                "logRecords": [{
                    "timeUnixNano": str(time.time_ns()),
                    "severityText": "INFO",
                    "severityNumber": 9,  # SEVERITY_NUMBER_INFO
                    "body": {"stringValue": message},
                }],
            }],
        }]
    }
    _post(f"{endpoint}/v1/logs", payload)


def _post(url: str, payload: dict) -> None:
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=5) as resp:
        if resp.status not in (200, 202):
            raise RuntimeError(f"unexpected status {resp.status}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("signal", choices=["trace", "log"])
    parser.add_argument("--endpoint", required=True, help="e.g. http://localhost:14318 (OTLP/HTTP base, no trailing /v1/...)")
    parser.add_argument("--service", required=True)
    parser.add_argument("--message", default="hello from send-raw-otlp.py", help="log signal only")
    args = parser.parse_args()

    if args.signal == "trace":
        trace_id = send_trace(args.endpoint, args.service)
        print(f"Sent trace_id={trace_id}")
    else:
        send_log(args.endpoint, args.service, args.message)
        print("Sent log record.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 — CLI tool, print and exit non-zero
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
