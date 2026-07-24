/**
 * frontend — AUTO-instrumented via the OpenTelemetry Operator (see
 * ../../operator/instrumentation/nodejs-instrumentation.yaml and
 * ../../docs/DECISIONS.md ADR-031). No tracer/exporter is configured
 * anywhere in this file — that is entirely the auto-instrumentation
 * webhook's job (NODE_OPTIONS require-hook injected into this
 * container at pod creation time, see ../../operator/examples/README.md).
 *
 * The only OpenTelemetry-aware code here is the log formatter reading
 * the already-active span via @opentelemetry/api (a no-op interface
 * package, not an SDK) so JSON logs carry trace_id/span_id — see
 * package.json's "_note_on_opentelemetry_api".
 */
const express = require("express");
const pino = require("pino");
const pinoHttp = require("pino-http");
const { trace } = require("@opentelemetry/api");

const SERVICE_NAME = "frontend";
const ORDER_SERVICE_URL = process.env.ORDER_SERVICE_URL || "http://order-service.otel-demo.svc.cluster.local:8000";
const PORT = process.env.PORT || 3000;

const logger = pino({
  formatters: {
    level(label) {
      return { severity: label.toUpperCase() };
    },
    log(payload) {
      const span = trace.getActiveSpan();
      if (span) {
        const ctx = span.spanContext();
        return { ...payload, trace_id: ctx.traceId, span_id: ctx.spanId, "service.name": SERVICE_NAME };
      }
      return { ...payload, "service.name": SERVICE_NAME };
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  messageKey: "message",
});

const app = express();
app.use(express.json());
app.use(pinoHttp({ logger }));

app.get("/health", (req, res) => res.json({ status: "ok" }));
app.get("/ready", (req, res) => res.json({ status: "ready" }));

app.get("/", async (req, res) => {
  try {
    const response = await fetch(`${ORDER_SERVICE_URL}/orders`, { method: "POST" });
    const body = await response.json();
    req.log.info({ order_id: body.order_id }, "Order flow completed");
    res.status(response.status).json({ frontend: "ok", order: body });
  } catch (err) {
    req.log.error({ err: err.message }, "Failed to reach order-service");
    res.status(502).json({ frontend: "error", message: "order-service unreachable" });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  logger.info({ port: PORT }, "frontend listening");
});
