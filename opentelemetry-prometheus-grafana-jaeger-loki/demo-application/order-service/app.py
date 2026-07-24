"""order-service — MANUALLY instrumented (see ../../docs/DECISIONS.md
ADR-031). The OpenTelemetry SDK is configured explicitly in this file
(setup_telemetry()), not injected by the Operator's auto-instrumentation
webhook — this Deployment carries no
`instrumentation.opentelemetry.io/inject-python` annotation, see
../../demo-application/kubernetes/order-service/deployment.yaml.

Demonstrates: a custom span (order.create), custom business metrics
(orders_total, order_processing_duration), structured JSON logs with
trace_id/span_id correlation, and a downstream call chain to
inventory-service and payment-service with configurable timeout/retry.
"""
import json
import logging
import os
import random
import time
import uuid

import httpx
import uvicorn
from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from opentelemetry import trace, metrics, context
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.trace import Status, StatusCode

SERVICE_NAME = "order-service"
SERVICE_VERSION = os.environ.get("SERVICE_VERSION", "1.0.0")
OTLP_ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector-gateway.opentelemetry.svc.cluster.local:4317")
INVENTORY_SERVICE_URL = os.environ.get("INVENTORY_SERVICE_URL", "http://inventory-service.otel-demo.svc.cluster.local:8000")
PAYMENT_SERVICE_URL = os.environ.get("PAYMENT_SERVICE_URL", "http://payment-service.otel-demo.svc.cluster.local:8000")
TIMEOUT_MS = int(os.environ.get("TIMEOUT_MS", "3000"))
RETRY_ATTEMPTS = int(os.environ.get("RETRY_ATTEMPTS", "2"))


def setup_telemetry():
    resource = Resource.create({
        ResourceAttributes.SERVICE_NAME: SERVICE_NAME,
        ResourceAttributes.SERVICE_VERSION: SERVICE_VERSION,
        ResourceAttributes.DEPLOYMENT_ENVIRONMENT: "lab",
    })

    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT, insecure=True)))
    trace.set_tracer_provider(tracer_provider)

    metric_reader = PeriodicExportingMetricReader(
        OTLPMetricExporter(endpoint=OTLP_ENDPOINT, insecure=True), export_interval_millis=15000
    )
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)

    return trace.get_tracer(SERVICE_NAME, SERVICE_VERSION), metrics.get_meter(SERVICE_NAME, SERVICE_VERSION)


tracer, meter = setup_telemetry()

orders_total = meter.create_counter("orders_total", description="Total orders created, by status")
orders_failed_total = meter.create_counter("orders_failed_total", description="Total orders that failed")
order_processing_duration = meter.create_histogram(
    "order_processing_duration", unit="ms", description="End-to-end order processing time"
)
active_requests = meter.create_up_down_counter("active_requests", description="In-flight requests")


class TraceContextJsonFormatter(logging.Formatter):
    """Structured JSON logs with trace_id/span_id injected from the
    currently active span — see ../../docs/06-logs.md 'Trace ID and
    span ID injection' and ../../docs/08-telemetry-correlation.md.
    """

    def format(self, record):
        span = trace.get_current_span()
        span_ctx = span.get_span_context()
        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "severity": record.levelname,
            "service.name": SERVICE_NAME,
            "message": record.getMessage(),
        }
        if span_ctx.is_valid:
            payload["trace_id"] = format(span_ctx.trace_id, "032x")
            payload["span_id"] = format(span_ctx.span_id, "016x")
        for key in ("order_id", "customer_type"):
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        return json.dumps(payload)


logger = logging.getLogger(SERVICE_NAME)
logger.setLevel(logging.INFO)
_handler = logging.StreamHandler()
_handler.setFormatter(TraceContextJsonFormatter())
logger.addHandler(_handler)

app = FastAPI(title="order-service")
FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    return {"status": "ready"}


async def call_downstream(client: httpx.AsyncClient, url: str, order_id: str):
    """Calls a downstream service with the configured timeout and a
    bounded retry count — never retries indefinitely (see
    ../../docs/DECISIONS.md and ../../docs/21-troubleshooting.md
    'Sending queue full' for why unbounded retries are a real risk)."""
    last_exc = None
    for attempt in range(1, RETRY_ATTEMPTS + 2):
        try:
            resp = await client.post(url, json={"order_id": order_id}, timeout=TIMEOUT_MS / 1000)
            resp.raise_for_status()
            return resp.json()
        except (httpx.HTTPStatusError, httpx.TimeoutException, httpx.ConnectError) as exc:
            last_exc = exc
            logger.warning(
                "downstream call attempt %d/%d to %s failed: %s",
                attempt, RETRY_ATTEMPTS + 1, url, exc,
                extra={"order_id": order_id},
            )
    raise last_exc


@app.post("/orders")
async def create_order():
    active_requests.add(1)
    start = time.time()
    order_id = f"order-{uuid.uuid4().hex[:8]}"
    customer_type = random.choice(["standard", "premium"])

    # Custom span for the business operation, distinct from the
    # framework-level span FastAPIInstrumentor already creates for the
    # HTTP request itself — see ../../docs/04-distributed-tracing.md
    # "Root span, parent span, child span".
    with tracer.start_as_current_span("order.create") as span:
        span.set_attribute("order.id", order_id)
        span.set_attribute("customer.type", customer_type)
        logger.info("Creating order", extra={"order_id": order_id})

        try:
            async with httpx.AsyncClient() as client:
                with tracer.start_as_current_span("inventory.check") as inv_span:
                    inventory_result = await call_downstream(client, f"{INVENTORY_SERVICE_URL}/check", order_id)
                    available = inventory_result.get("available", False)
                    inv_span.set_attribute("inventory.available", available)
                    if not available:
                        span.set_status(Status(StatusCode.ERROR, "inventory unavailable"))
                        orders_failed_total.add(1, {"reason": "inventory_unavailable"})
                        logger.warning("Order failed: inventory unavailable", extra={"order_id": order_id})
                        return JSONResponse(status_code=409, content={"order_id": order_id, "status": "failed", "reason": "inventory_unavailable"})

                with tracer.start_as_current_span("payment.authorize") as pay_span:
                    pay_span.set_attribute("payment.provider", "mock-processor")
                    payment_result = await call_downstream(client, f"{PAYMENT_SERVICE_URL}/authorize", order_id)
                    authorized = payment_result.get("authorized", False)
                    if not authorized:
                        span.set_status(Status(StatusCode.ERROR, "payment declined"))
                        orders_failed_total.add(1, {"reason": "payment_declined"})
                        logger.error("Order failed: payment declined", extra={"order_id": order_id})
                        return JSONResponse(status_code=402, content={"order_id": order_id, "status": "failed", "reason": "payment_declined"})

            orders_total.add(1, {"status": "success"})
            span.set_status(Status(StatusCode.OK))
            logger.info("Order created successfully", extra={"order_id": order_id})
            return {"order_id": order_id, "status": "created", "customer_type": customer_type}

        except Exception as exc:  # noqa: BLE001 — deliberately broad: any downstream failure becomes a failed-order response, not a 500
            span.record_exception(exc)
            span.set_status(Status(StatusCode.ERROR, str(exc)))
            orders_failed_total.add(1, {"reason": "downstream_error"})
            logger.error("Order failed: downstream error: %s", exc, extra={"order_id": order_id})
            return JSONResponse(status_code=502, content={"order_id": order_id, "status": "failed", "reason": "downstream_error"})
        finally:
            duration_ms = (time.time() - start) * 1000
            order_processing_duration.record(duration_ms, {"customer_type": customer_type})
            active_requests.add(-1)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
