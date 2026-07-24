"""inventory-service — AUTO-instrumented (see ../../docs/DECISIONS.md
ADR-031). This file contains NO OpenTelemetry SDK setup at all — trace
context, spans, and metrics are added entirely by the Operator's
auto-instrumentation webhook (../../operator/instrumentation/python-
instrumentation.yaml), triggered by an annotation on this service's
Deployment, not by anything in this source file. Compare directly with
../order-service/app.py's explicit setup_telemetry().
"""
import json
import logging
import os
import random
import time

import uvicorn
from fastapi import FastAPI

SERVICE_NAME = "inventory-service"

# In-memory stock levels — no external database, per this lab's demo-app
# design constraint (root docs/DECISIONS.md). Deliberately simple: this
# lab teaches observability, not inventory-management correctness.
STOCK = {"default-sku": 500}
LOW_STOCK_PROBABILITY = float(os.environ.get("LOW_STOCK_PROBABILITY", "0.05"))


class OtelAwareJsonFormatter(logging.Formatter):
    """Reads the otelTraceID/otelSpanID LogRecord attributes the
    Operator's Python auto-instrumentation injects when
    OTEL_PYTHON_LOG_CORRELATION=true (set in the Instrumentation CRD) —
    this service never looks up trace context itself, unlike
    order-service's manual formatter."""

    def format(self, record):
        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "severity": record.levelname,
            "service.name": SERVICE_NAME,
            "message": record.getMessage(),
        }
        trace_id = getattr(record, "otelTraceID", None)
        span_id = getattr(record, "otelSpanID", None)
        if trace_id and trace_id != "0":
            payload["trace_id"] = trace_id
        if span_id and span_id != "0":
            payload["span_id"] = span_id
        if hasattr(record, "order_id"):
            payload["order_id"] = record.order_id
        return json.dumps(payload)


logger = logging.getLogger(SERVICE_NAME)
logger.setLevel(logging.INFO)
_handler = logging.StreamHandler()
_handler.setFormatter(OtelAwareJsonFormatter())
logger.addHandler(_handler)

app = FastAPI(title="inventory-service")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    return {"status": "ready"}


@app.post("/check")
def check_inventory(payload: dict):
    order_id = payload.get("order_id", "unknown")
    # A small, configurable chance of "out of stock" so the demo app can
    # produce a real inventory-unavailable failure path without the
    # learner needing to manually deplete STOCK first.
    available = random.random() > LOW_STOCK_PROBABILITY and STOCK["default-sku"] > 0
    if available:
        STOCK["default-sku"] -= 1
        logger.info("Inventory check passed", extra={"order_id": order_id})
    else:
        logger.warning("Inventory check failed: item unavailable", extra={"order_id": order_id})
    return {"order_id": order_id, "available": available, "remaining": STOCK["default-sku"]}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
