# Lab 15: JWT Authentication

## Objective

Require a valid JWT for calls to `order-service`, and prove that `RequestAuthentication` alone does **not** reject missing tokens — only pairing it with an `AuthorizationPolicy` requiring `requestPrincipals` does.

## Concepts exercised

`RequestAuthentication` with inline JWKS (`../docs/06-service-security-and-mtls.md`), the two-resource pairing this lab explicitly calls out as commonly misunderstood.

## Prerequisites

Labs 01, 03, 14 complete. Python 3 with `pyjwt` and `cryptography` installed locally (`pip install --user pyjwt cryptography`) — this lab generates its own throwaway signing key; no remote IdP, nothing committed to the repository.

## Steps

1. **Generate a throwaway RSA signing key** (git-ignored, under `.generated/jwt/`):
   ```bash
   mkdir -p .generated/jwt
   openssl genrsa -out .generated/jwt/test-key.pem 2048
   openssl rsa -in .generated/jwt/test-key.pem -pubout -out .generated/jwt/test-key-pub.pem
   ```

2. **Build the inline JWKS JSON from the public key**:
   ```bash
   python3 - <<'PYEOF'
   import json, base64
   from cryptography.hazmat.primitives import serialization

   with open(".generated/jwt/test-key-pub.pem", "rb") as f:
       pub = serialization.load_pem_public_key(f.read())
   numbers = pub.public_numbers()

   def b64url(n, length):
       return base64.urlsafe_b64encode(n.to_bytes(length, "big")).rstrip(b"=").decode()

   jwk = {
       "kty": "RSA", "use": "sig", "alg": "RS256", "kid": "istio-lab-test-key",
       "n": b64url(numbers.n, 256), "e": b64url(numbers.e, 3),
   }
   jwks = {"keys": [jwk]}
   with open(".generated/jwt/jwks.json", "w") as f:
       json.dump(jwks, f)
   print("Wrote .generated/jwt/jwks.json")
   PYEOF
   ```

3. **Mint a short-lived test JWT** matching `config/lab-settings.env`'s `JWT_TEST_ISSUER`/`JWT_TEST_AUDIENCE`:
   ```bash
   source config/lab-settings.env
   python3 - <<PYEOF
   import jwt, time
   with open(".generated/jwt/test-key.pem") as f:
       key = f.read()
   token = jwt.encode(
       {"iss": "${JWT_TEST_ISSUER}", "aud": "${JWT_TEST_AUDIENCE}", "sub": "lab-user",
        "iat": int(time.time()), "exp": int(time.time()) + 300},
       key, algorithm="RS256", headers={"kid": "istio-lab-test-key"},
   )
   with open(".generated/jwt/token.txt", "w") as f:
       f.write(token)
   print(token)
   PYEOF
   ```

4. **Render and apply the `RequestAuthentication` + `AuthorizationPolicy` template** (`policies/requestauthentication/jwt-requestauth.yaml.tpl` — a single file containing both resources: `RequestAuthentication` validates any presented token; the paired `AuthorizationPolicy` is what actually requires one):
   ```bash
   export JWKS_JSON="$(cat .generated/jwt/jwks.json)"
   envsubst < policies/requestauthentication/jwt-requestauth.yaml.tpl > .generated/jwt/rendered.yaml
   kubectl apply -f .generated/jwt/rendered.yaml
   ```

**Note on which client to test from**: steps 5–7 deliberately use `demo-client`, not the `frontend` pod. Lab 14's `allow-frontend-to-order.yaml` already permits `frontend`'s SPIFFE identity to call `order-service` with **no token at all** — that `AuthorizationPolicy` is still active and additive with this lab's new one, so testing from `frontend` would not demonstrate JWT enforcement (it would succeed either way, via the older identity-based rule). `demo-client` matches neither the frontend-identity allow rule nor (without a token) this lab's JWT-presence allow rule, so it correctly demonstrates the denial. With a valid token attached, `demo-client` **is** allowed — this lab's `AuthorizationPolicy` grants access based purely on `requestPrincipals` (a valid JWT), regardless of the caller's own workload identity, which is a meaningfully different, broader grant than Lab 14's principal-based one.

5. **Call `order-service` with an invalid/garbage token — confirm it's rejected**:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
     -H "Authorization: Bearer not-a-real-token" http://order-service/
   ```
   Expect `401` — `RequestAuthentication` rejects any *presented but invalid* token on its own, without needing the paired `AuthorizationPolicy`.

6. **Call with no token at all**:
   ```bash
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' http://order-service/
   ```
   Expect `403` — this comes from the paired `AuthorizationPolicy`'s `requestPrincipals` requirement (and Lab 14's default-deny), not from `RequestAuthentication` itself, which alone would have let a token-less request through.

7. **Call with the valid token from step 3**:
   ```bash
   TOKEN="$(cat .generated/jwt/token.txt)"
   kubectl exec -n istio-demo demo-client -- curl -s -o /dev/null -w '%{http_code}\n' \
     -H "Authorization: Bearer ${TOKEN}" http://order-service/
   ```
   Expect success.

## Validation

The three-state matrix (invalid token → `401`; no token → `403`; valid token → success) all match expectations.

## Failure scenarios to notice

Mint a token with `"exp": int(time.time()) - 10` (already expired) and repeat step 7 — expect the same rejection as the invalid-token case, since expiry is validated the same way signature validity is. This is a real, common cause of "my JWT auth suddenly stopped working" in production, worth distinguishing from an outright invalid signature.

## Cleanup

```bash
kubectl delete -f .generated/jwt/rendered.yaml
```
`.generated/jwt/` is already git-ignored; delete it locally if you want to remove the throwaway key material entirely.

## Reflection

Why does this lab use an inline JWKS rather than `jwksUri` pointed at a real identity provider? What operational capability does inline JWKS give up (`../docs/06-service-security-and-mtls.md`'s production-considerations note), and what would you need to add to make this production-appropriate?
