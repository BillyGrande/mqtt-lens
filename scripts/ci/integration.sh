#!/usr/bin/env bash
# Integration environment: start EMQX and Keycloak, wait for health, smoke test, tear down.
# Exits non-zero on any failure. Used by `make integration` and CI.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
COMPOSE=(docker compose -f deploy/docker-compose.yml)

cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "integration: failed (exit $rc), container logs follow" >&2
    "${COMPOSE[@]}" logs --no-color --tail=80 >&2 || true
  fi
  "${COMPOSE[@]}" down -v --remove-orphans >&2 || true
  exit "$rc"
}
trap cleanup EXIT

echo "integration: starting EMQX and Keycloak (waiting for both health checks)"
"${COMPOSE[@]}" up -d --wait --wait-timeout 300

echo "integration: EMQX smoke test (subscribe, publish one message, receive it)"
# The EMQX image has no MQTT client. The emqx CLI evaluates Erlang inside the node.
out="$("${COMPOSE[@]}" exec -T emqx sh -c 'emqx eval "$(cat)"' < scripts/ci/emqx-smoke.erl)"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^SMOKE_OK' || { echo "integration: EMQX smoke test failed" >&2; exit 1; }

echo "integration: Keycloak smoke test (OpenID configuration of realm example)"
conf="$(curl -fsS --max-time 20 http://127.0.0.1:8080/realms/example/.well-known/openid-configuration)"
printf '%s' "$conf" | grep -q '"issuer"' || { echo "integration: no issuer in OIDC configuration" >&2; exit 1; }
printf '%s' "$conf" | grep -q '/realms/example' || { echo "integration: wrong realm in OIDC configuration" >&2; exit 1; }

echo "integration: all checks passed"
