# Kubernetes Gateway API CRDs

This lab uses the Kubernetes Gateway API's `standard` install channel, pinned to **v1.4.0** (see `../../config/versions.env` `GATEWAY_API_VERSION` and root `docs/VERSIONS.md` "Phase 4 addendum" for why v1.4.0 was chosen over the newer v1.6.1).

## Why these CRDs aren't vendored into this repo

`scripts/install.sh` applies the CRDs directly from the pinned upstream release URL (`GATEWAY_API_CRDS_URL` in `../../config/versions.env`) rather than committing a local copy — Gateway API CRDs are large, upstream-maintained, and this lab wants exactly the pinned upstream bytes, not a repo-local copy that could silently drift from the real release.

## Ownership and cleanup

`scripts/install.sh` only applies these CRDs if they aren't already present (`crd_exists gateways.gateway.networking.k8s.io`) and, when it does install them, writes `.generated/gateway-api-crds-owned.marker` — this is how `scripts/uninstall.sh` knows whether it's safe to remove them later (only if this lab actually installed them, never if they pre-existed for some other consumer).

## Manual application (equivalent to what install.sh does)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

## Relationship to Istio's own `Gateway` resource

This lab's demo ingress (`../../demo/gateway/`) uses Istio's own `networking.istio.io/v1` `Gateway` + `VirtualService` resources, not the Kubernetes Gateway API's `Gateway`/`HTTPRoute` — see `../../docs/07-gateways-and-ingress.md` for why, and for what a Gateway-API-native ingress setup would look like instead. The Gateway API CRDs are still installed because Istio's own chart and `istioctl analyze` expect them to be present (Istio increasingly treats Gateway API as a first-class, sometimes required, dependency even for Istio-API-based configurations), not because this lab's demo ingress directly instantiates Gateway API objects itself.
