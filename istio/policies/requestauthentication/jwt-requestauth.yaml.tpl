# Lab: labs/lab-15-jwt-authentication.md
#
# Template, not a static manifest — the ${JWKS_JSON} placeholder is
# filled in by labs/lab-15-jwt-authentication.md's setup steps from a
# LOCALLY GENERATED test signing key (never a remote IdP, never
# committed — see ../../config/lab-settings.env JWT_TEST_ISSUER/
# JWT_TEST_AUDIENCE and ../../.generated/jwt/, git-ignored). Uses
# inline `jwks` rather than `jwksUri` specifically so istiod never
# needs outbound network access to validate tokens — fully offline
# after the one-time local key generation step.
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: jwt-test-issuer
  namespace: istio-demo
  labels:
    app.kubernetes.io/part-of: istio-learning-lab
spec:
  selector:
    matchLabels: {app: order-service}
  jwtRules:
    - issuer: "${JWT_TEST_ISSUER}"
      audiences: ["${JWT_TEST_AUDIENCE}"]
      jwks: |
        ${JWKS_JSON}
---
# RequestAuthentication alone only VALIDATES a presented token — it
# does not by itself require one. This AuthorizationPolicy is what
# actually rejects requests with no/invalid token, combining
# `requestPrincipals` (which is only non-empty for successfully
# validated JWTs) with the DENY-by-default posture already established
# by ../authorization/namespace-default-deny.yaml.
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: require-jwt-for-order-service
  namespace: istio-demo
  labels:
    app.kubernetes.io/part-of: istio-learning-lab
spec:
  selector:
    matchLabels: {app: order-service}
  action: ALLOW
  rules:
    - from:
        - source:
            requestPrincipals: ["${JWT_TEST_ISSUER}/*"]
