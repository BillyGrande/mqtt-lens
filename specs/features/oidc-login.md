---
type: feature
title: OIDC login
description: Keycloak client settings and the Authorization Code + PKCE login flow.
status: draft
tags: [auth, oidc, security]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §4.1-4.2
---

# Keycloak client

- Confidential client `mqtt-lens`. Standard flow only.
- Off: direct access grants, implicit flow, service account, front-channel logout.
- `pkce.code.challenge.method = S256` (Keycloak rejects requests without PKCE).
- One exact redirect URI: `https://<host>/auth/callback`. Web origin: `https://<host>`. No wildcards.
- Client authentication: client secret for the MVP. Later: `private_key_jwt` (oidcc supports it).
- Mapper: `groups` claim in the ID token, full path on.
- The upstream IdP enforces MFA before Keycloak gets the identity.

# Login flow

1. `GET /auth/login`
   - Make `state` (256 bit), `nonce` (256 bit), and a PKCE verifier with `:crypto.strong_rand_bytes/1`.
   - Keep them in `Auth.Flows` (ETS, TTL 5 min, max 10 000 entries; when full, return 503).
   - Set cookie `__Host-mlens-flow` = flow ID (HttpOnly, Secure, SameSite=Lax, Max-Age=300).
   - Redirect to Keycloak with `response_type=code`, `scope=openid`, `code_challenge_method=S256`.
2. `GET /auth/callback?code&state`
   - Get the flow by cookie, then delete it (one use only).
   - Compare `state` with `Plug.Crypto.secure_compare/2`. If it does not match, return 400 and log `login_failed`.
   - Exchange the code with `oidcc` (back channel, TLS with certificate checks, 10 s timeout).
   - Check the ID token:
     - signature with JWKS (cached by the oidcc provider worker; refreshed on an unknown `kid`, max 1 refresh per minute)
     - `alg` in {RS256, PS256, ES256}; never `none`, never HS*
     - `iss` = the configured issuer (exact match)
     - `aud` contains `mqtt-lens`; `azp` = `mqtt-lens` when present
     - `exp`, `iat` with max 60 s clock skew
     - `nonce` = the flow nonce
   - Map `groups` to roles ([authorization](/features/authorization.md)). **No role → 403 page, no session.**
   - Make a new session ([sessions](/features/sessions.md)) and redirect to `/`.
   - Keep only `sub`, `email`, `name`, roles and the `id_token` (for logout).
     Do not keep access or refresh tokens. The app does not call APIs for the user.
3. `DELETE /auth/logout` (a form with the CSRF token)
   - Delete the session. Close the user's sockets ([sessions](/features/sessions.md)).
   - Redirect to the Keycloak `end_session_endpoint` with `id_token_hint` and `post_logout_redirect_uri`.

# Citations

1. [Threat model](/architecture/threat-model.md)
2. [Sessions](/features/sessions.md)
