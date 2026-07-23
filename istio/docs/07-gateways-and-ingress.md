# Gateways and Ingress

## Definition

A **Gateway** is a standalone Envoy proxy (no application container, no sidecar semantics) sitting at the mesh's edge, handling north-south traffic (`01-service-mesh-fundamentals.md`). Istio exposes two independent APIs for configuring one: its own native `Gateway`/`VirtualService` pair, and the upstream Kubernetes **Gateway API**. This lab uses the native API for its own demo and documents, but does not deploy, the Gateway API path.

## Istio's native Gateway + VirtualService

`demo/gateway/gateway.yaml` defines a `Gateway` resource selecting the `istio-ingress` Deployment (`selector: app: istio-ingress` — the gateway workload installed via `install/ingress-gateway-values-{minimum,recommended}.yaml`, itself just Istiod-managed Envoy with no sidecar-injection semantics, configured instead directly via Helm values and its own `Gateway`/`VirtualService` resources) and the host/port/protocol it listens on. `demo/gateway/virtualservice.yaml` attaches to that `Gateway` (via `spec.gateways`, distinguishing it from the east-west `VirtualService`s in `demo/traffic/` which have no `gateways` field and therefore apply to sidecars only) and routes matched external requests to `frontend`.

## Why this lab's ingress Service is `ClusterIP`, not `LoadBalancer`

Both `install/ingress-gateway-values-minimum.yaml` and `-recommended.yaml` set `service.type: ClusterIP` deliberately. This is a homelab/on-prem Vagrant cluster (`../../auto-setup-default-kube-env/`) with no cloud load-balancer controller — a `LoadBalancer`-type Service would sit `<pending>` forever. This lab's documented access pattern is **`kubectl port-forward`** to the ingress gateway Service (`examples/application-access.md`, `make port-forward-ingress` in the Makefile) — a deliberate, explained choice (root `docs/DECISIONS.md` ADR-023), not an oversight. Production deployments on a cloud provider would instead use `LoadBalancer` or a `NodePort` behind an external LB — documented in `11-production-design.md` as the production alternative, not implemented here.

## The Kubernetes Gateway API alternative (documented, not installed)

`install/gateway-api/README.md` explains the vendor-neutral, `gateway.networking.k8s.io`-based alternative API — `GatewayClass`/`Gateway`/`HTTPRoute` — which Istio also implements as a controller. This lab's `install.sh` conditionally installs the Gateway API CRDs (pinned `v1.4.0`, tracked via `.generated/gateway-api-crds-owned.marker` so `uninstall.sh` only removes them if this lab's install actually put them there — never removing CRDs another tool might depend on) because some `istioctl analyze` checks and future-compatibility expect the CRDs to at least be present, but **no demo traffic in this lab is routed through Gateway API resources** — the native `Gateway`/`VirtualService` pair is what's actually exercised, with the Gateway API path documented as the increasingly-recommended direction for new Istio ingress configuration going forward.

## Request flow: external client to frontend

```mermaid
sequenceDiagram
    participant Client
    participant PF as kubectl port-forward
    participant GW as istio-ingress Envoy\n(Gateway resource)
    participant Frontend as frontend sidecar

    Client->>PF: HTTP request to localhost:8080
    PF->>GW: Forwarded to istio-ingress Service (ClusterIP)
    Note over GW: Gateway resource matched (host/port);\nVirtualService (gateways: istio-ingress) route matched
    GW->>Frontend: mTLS to frontend pod's sidecar
    Frontend-->>GW: Response
    GW-->>PF: Response
    PF-->>Client: Response
```

`config/endpoints.env`'s `INGRESS_GATEWAY_LOCAL_PORT=8080` is the local port `make port-forward-ingress` binds — see `labs/lab-05-ingress-gateway.md`.

## Failure modes

- Expecting a `LoadBalancer` Service to get an external IP on this cluster — it won't; this lab's `ClusterIP` + port-forward pattern is the intended access method, documented explicitly so this isn't mistaken for a bug.
- Applying a `VirtualService` for east-west routing but forgetting the `gateways` field, causing it to unintentionally also apply mesh-wide — or, conversely, adding a `gateways` field to what was meant to be an east-west rule and having it silently not apply to sidecar traffic at all.
- Confusing the `Gateway` **resource** (Istio config object) with the `istio-ingress` **workload** (the actual Envoy Deployment/Pod) — a `Gateway` resource with no matching-labeled workload behind it produces no error, just no effect; `istioctl analyze` flags this.

## Production considerations

Real production traffic entry usually pairs a cloud/hardware load balancer in front of the ingress gateway Service (`LoadBalancer` type or an external LB pointed at `NodePort`s) — `11-production-design.md` covers this; this lab's port-forward pattern is homelab-appropriate only and explicitly not a production recommendation.

## Interview-level explanation

*"How does external traffic actually reach a pod in an Istio mesh?"* — It enters through the ingress gateway — a standalone Envoy Deployment (no sidecar involved at this hop) configured by a `Gateway` resource (which host/port/protocol to accept) plus a `VirtualService` scoped to that gateway (where to route it). From there it's mTLS'd to the destination pod's own sidecar exactly like any east-west hop. The gateway workload itself is exposed to the outside world via a normal Kubernetes Service — `LoadBalancer` in a cloud environment, or, as in this lab's bare-metal homelab cluster, `ClusterIP` behind a deliberate `kubectl port-forward` since there's no cloud LB controller to satisfy a `LoadBalancer` type.
