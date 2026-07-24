"""payment-service — MANUALLY instrumented (see ../../docs/DECISIONS.md
ADR-031). Explicit OpenTelemetry SDK setup, like order-service. This is
also the service every controlled-failure lab targets — LATENCY_MS and
FAILURE_PERCENT are read fresh on every request from environment
variables, which scripts/inject-latency.sh and scripts/inject-errors.sh
change via `kubectl set env` (triggering a rolling restart) — see
labs/lab-10-*.md onward and ../../docs/21-troubleshooting.md.
"""
import json
import logging
import os
import random
import time

import uvicorn
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from opentelemetry import trace, metrics
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.trace import Status, StatusCode

SERVICE_NAME = "payment-service"
SERVICE_VERSION = os.environ.get("SERVICE_VERSION", "1.0.0")
OTLP_ENDPOINT = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector-gateway.opentelemetry.svc.cluster.local:4317")


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

payment_authorizations_total = meter.create_counter("payment_authorizations_total", description="Total payment authorization attempts")
payment_failures_total = meter.create_counter("payment_failures_total", description="Total declined/failed payment authorizations")


class TraceContextJsonFormatter(logging.Formatter):
    def format(self, record):
        span_ctx = trace.get_current_span().get_span_context()
        payload = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "severity": record.levelname,
            "service.name": SERVICE_NAME,
            "message": record.getMessage(),
        }
        if span_ctx.is_valid:
            payload["trace_id"] = format(span_ctx.trace_id, "032x")
            payload["span_id"] = format(span_ctx.span_id, "016x")
        if hasattr(record, "order_id"):
            payload["order_id"] = record.order_id
        return json.dumps(payload)


logger = logging.getLogger(SERVICE_NAME)
logger.setLevel(logging.INFO)
_handler = logging.StreamHandler()
_handler.setFormatter(TraceContextJsonFormatter())
logger.addHandler(_handler)

app = FastAPI(title="payment-service")
FastAPIInstrumentor.instrument_app(app)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    return {"status": "ready"}


@app.post("/authorize")
async def authorize(payload: dict):
    order_id = payload.get("order_id", "unknown")

    # Read fresh on every request — see module docstring and
    # scripts/inject-latency.sh / scripts/inject-errors.sh.
    latency_ms = int(os.environ.get("LATENCY_MS", "0"))
    failure_percent = float(os.environ.get("FAILURE_PERCENT", "0"))

    with tracer.start_as_current_span("payment.authorize") as span:
        span.set_attribute("payment.provider", "mock-processor")
        span.set_attribute("order.id", order_id)

        if latency_ms > 0:
            with tracer.start_as_current_span("payment.provider_call"):
                time.sleep(latency_ms / 1000)

        payment_authorizations_total.add(1)
        declined = (random.random() * 100) < failure_percent

        if declined:
            span.set_status(Status(StatusCode.ERROR, "payment declined"))
            payment_failures_total.add(1, {"reason": "declined"})
            logger.error("Payment declined for order", extra={"order_id": order_id})
            return JSONResponse(status_code=402, content={"order_id": order_id, "authorized": False, "reason": "declined"})

        span.set_status(Status(StatusCode.OK))
        logger.info("Payment authorized", extra={"order_id": order_id})
        return {"order_id": order_id, "authorized": True}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
