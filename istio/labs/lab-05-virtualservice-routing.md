# Lab 05: VirtualService Routing Basics

## Objective

Exercise `VirtualService`'s core HTTP matching primitives — exact path, prefix path, and URI rewrite — in isolation, tested directly against `order-service` from inside the mesh (not through the ingress gateway), before layering subsets/canary/header-routing on top in later labs.

## Concepts exercised

`VirtualService` `match`/`rewrite` mechanics and route-priority (first-match-wins) semantics (`../docs/05-traffic-management.md`).

## Prerequisites

Labs 01, 03 complete.

## Steps

1. **Apply the routing rules**:
   ```bash
   kubectl apply -f demo/traffic/virtualservice-path-routing.yaml
   ```
   Inspect the file — it demonstrates exact path match, prefix path match, and a URI rewrite, all in one `VirtualService` targeting `order-service` directly.

2. **Test the exact-match route**:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/<exact path from the manifest>
   ```

3. **Test the prefix-match route** with a few different suffixes, confirming all of them match:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/<prefix>/anything-here
   ```

4. **Test the rewrite** — confirm (via `whoami`'s echoed request path in its response body) that the path Envoy actually forwards upstream differs from the path you requested:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s http://order-service/<rewrite-triggering-path> | grep -i "GET /"
   ```
   Compare the path `whoami` reports receiving against the path you actually requested.

## Validation

Exact match, prefix match, and rewrite each produce the expected routing/rewrite behavior, confirmed by inspecting `whoami`'s echoed request details.

## Failure scenarios to notice

Per `../docs/05-traffic-management.md`'s route-priority note: reorder the `http` match rules in a local copy of the manifest so a broader prefix match is listed before a more specific exact match, reapply, and observe the specific route become unreachable — first-match-wins means order is significant, not just specificity. Restore the original file afterward.

## Cleanup

Leave `virtualservice-path-routing.yaml` applied, or remove it if a later lab's `VirtualService` for `order-service` would conflict:
```bash
kubectl delete -f demo/traffic/virtualservice-path-routing.yaml
```

## Reflection

Why does Istio evaluate `VirtualService` HTTP match rules in listed order rather than by specificity (most-specific-match-wins, the way some other routing systems behave)? What does that imply about how you should structure a `VirtualService` with both a specific path match and a catch-all default?
