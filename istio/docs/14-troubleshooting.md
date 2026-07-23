# Troubleshooting

A symptom-first reference. Each row names the first thing to check, not necessarily the eventual root cause — start at the symptom, follow the debugging workflow in `10-configuration-analysis.md` from there.

## Sidecar and injection issues

| Symptom | First check | Likely cause | Reference |
| --- | --- | --- | --- |
| Pod has no sidecar container after creation | `kubectl get ns <ns> -o yaml \| grep istio.io/rev` | Namespace not labeled with the expected revision | `02-istio-architecture.md` |
| Pod stuck in `ContainerCreating`, networking broken | `kubectl describe pod`, check `istio-cni-node` DaemonSet | Istio CNI plugin not running/unhealthy on that node, or Cilium chaining not configured | `04-istio-cni-and-cilium.md` |
| Sidecar present but proxy seems to ignore new config | `istioctl proxy-status` | Proxy is `STALE`, not `SYNCED` | `10-configuration-analysis.md` |

## Traffic routing issues

| Symptom | First check | Likely cause | Reference |
| --- | --- | --- | --- |
| Requests never reach the expected subset (v2) | `istioctl analyze` | `VirtualService` references a subset the `DestinationRule` doesn't define | `05-traffic-management.md` |
| Canary split looks wildly off from configured weight on a small test | Request count in the test | Weighted routing is probabilistic; small samples don't converge to the exact percentage | `05-traffic-management.md` |
| A `VirtualService` you applied for east-west routing seems to also affect ingress traffic (or vice versa) | The resource's `gateways` field | Missing/incorrect `gateways` field scoping | `07-gateways-and-ingress.md` |
| External client can't reach the ingress gateway at all | Service type of `istio-ingress` | Expecting `LoadBalancer` to get an external IP on a bare-metal cluster — this lab uses `ClusterIP` + port-forward deliberately | `07-gateways-and-ingress.md` |

## Security issues

| Symptom | First check | Likely cause | Reference |
| --- | --- | --- | --- |
| Plaintext client unexpectedly still works under "strict" mTLS | `kubectl get peerauthentication -A` | `PeerAuthentication` not actually applied at the expected scope (namespace vs. workload-specific override) | `06-service-security-and-mtls.md` |
| A caller you expected to be denied is allowed | `AuthorizationPolicy` selectors and `namespace-default-deny.yaml` presence | Default-deny not applied in that namespace, or an overly broad allow rule | `06-service-security-and-mtls.md` |
| Unauthenticated requests (no JWT) still succeed despite a `RequestAuthentication` | Whether an `AuthorizationPolicy` `when` clause requires `request.auth.claims` | `RequestAuthentication` alone validates but does not require a JWT | `06-service-security-and-mtls.md` |
| A debug pod you just created can't reach anything | The namespace's `Sidecar` resource egress hosts | `Sidecar`-resource scoping applies to every proxy in that namespace, including new/debug pods | `05-traffic-management.md` |

## Resilience issues

| Symptom | First check | Likely cause | Reference |
| --- | --- | --- | --- |
| Requests fail faster than the configured timeout suggests they should | Per-try timeout vs. route timeout, and retry count | Retry attempts sharing a tight overall route timeout | `09-resilience-patterns.md` |
| Circuit breaker "doesn't trip" under test load | Actual concurrent request volume vs. configured pool limit | Backend responds fast enough that the test load never saturates the pool | `09-resilience-patterns.md` |
| Fault-injection abort rate looks off from the configured percentage | Sample size of the test | Statistical, not exact-count, behavior | `09-resilience-patterns.md` |

## Egress issues

| Symptom | First check | Likely cause | Reference |
| --- | --- | --- | --- |
| Call to an unregistered external host unexpectedly succeeds | Mesh-wide `outboundTrafficPolicy.mode` | Istio's actual default is `ALLOW_ANY` passthrough, not default-deny — only `Sidecar`-resource scoping or `REGISTRY_ONLY` restricts this | `08-egress-and-serviceentry.md` |
| Call to a registered `ServiceEntry` host still fails | The namespace's `Sidecar` resource egress hosts | `ServiceEntry` registers the destination but doesn't itself override `Sidecar`-resource scoping — both must agree | `08-egress-and-serviceentry.md` |
| DNS resolution itself fails inside a scoped namespace | `Sidecar` resource egress hosts includes `kube-system/*` | CoreDNS lives in `kube-system`, not `istio-system` — an easy namespace to omit when scoping egress | `08-egress-and-serviceentry.md`, `05-traffic-management.md` |

## Cilium/CNI-chaining issues

| Symptom | First check | Likely cause | Reference |
| --- | --- | --- | --- |
| `istio-cni-node` DaemonSet CrashLoopBackOff, or newly created pods have broken networking | `helm get values cilium -n kube-system` for `cni.exclusive`/`socketLB.hostNamespaceOnly` | Cilium not configured for CNI chaining before Istio CNI was installed | `04-istio-cni-and-cilium.md` |
| `make install` hard-fails before the `istio-cni` step | The printed remediation command | Expected, intentional gate — `scripts/install.sh` refuses to install Istio CNI against a non-chaining-ready Cilium | `04-istio-cni-and-cilium.md` |

## General diagnostic sequence

Always the same order, detailed in `10-configuration-analysis.md`: `istioctl analyze` → `istioctl proxy-status` → `istioctl proxy-config` on the specific proxy → only then suspect the application layer. `scripts/collect-debug-bundle.sh`/`make debug-bundle` automates gathering the artifacts (`analyze` output, `proxy-status`, relevant `proxy-config` dumps, pod descriptions, recent events) this sequence needs into one archive for offline review or sharing.

## Interview-level explanation

*"A user reports 'Istio isn't routing my traffic correctly.' What's your triage order?"* — Config-consistency first (`istioctl analyze` — catches most real mistakes cheaply), then push-state (`istioctl proxy-status` — is the relevant proxy even `SYNCED`), then ground-truth proxy state (`istioctl proxy-config` — what does the proxy actually hold, and does it match expectation), and only after all three come back clean do I start suspecting the application layer itself. Most "Istio isn't working" reports resolve at step one or two; jumping straight to application-level debugging without ruling those out first wastes time chasing the wrong layer.
