#!/usr/bin/env bash
# Shared helpers for the guardrail git hooks (sourced, not executed).
set -euo pipefail

DENYLIST="${MQTTLENS_DENYLIST:-$HOME/.config/mqtt-lens/denylist}"
EXPECTED_NAME="BillyGrande"
EXPECTED_EMAIL="23191012+BillyGrande@users.noreply.github.com"

require_denylist() {
  if [ ! -r "$DENYLIST" ]; then
    echo "guardrail: deny-list not found or not readable: $DENYLIST" >&2
    echo "guardrail: create it or set MQTTLENS_DENYLIST. Failing closed." >&2
    exit 1
  fi
}

# scan_stream LABEL: read text on stdin, print hits, return 1 on any hit.
scan_stream() {
  local label="$1" hits
  hits="$(grep -inEf <(grep -vE '^[[:space:]]*(#|$)' "$DENYLIST") || true)"
  if [ -n "$hits" ]; then
    echo "guardrail: deny-list hit in $label:" >&2
    printf "%s\n" "${hits//$'\n'/$'\n  '}" >&2
    return 1
  fi
  return 0
}

# scan_added_lines LABEL: read a unified diff on stdin, scan only added lines
# and report file + matching pattern.
scan_diff() {
  local label="$1" file="" line rc=0 pat
  while IFS= read -r line; do
    case "$line" in
      "+++ b/"*) file="${line#+++ b/}" ;;
      "+++ "*) ;;
      "+"*)
        while IFS= read -r pat; do
          case "$pat" in ''|'#'*) continue ;; esac
          if printf '%s\n' "${line:1}" | grep -iqE -e "$pat"; then
            echo "guardrail: deny-list hit in $label: file=${file:-?} pattern=$pat" >&2
            rc=1
          fi
        done < "$DENYLIST"
        ;;
    esac
  done
  return "$rc"
}

check_identity() {
  local n e
  n="$(git config user.name || true)"
  e="$(git config user.email || true)"
  if [ "$n" != "$EXPECTED_NAME" ] || [ "$e" != "$EXPECTED_EMAIL" ]; then
    echo "guardrail: wrong git identity: '$n <$e>'" >&2
    echo "guardrail: expected '$EXPECTED_NAME <$EXPECTED_EMAIL>' (repo-local config)." >&2
    exit 1
  fi
}

# chain_beads NAME ARGS...: run .beads/hooks/NAME if executable (stdin passes through).
chain_beads() {
  local name="$1" root
  shift
  root="$(git rev-parse --show-toplevel)"
  if [ -x "$root/.beads/hooks/$name" ]; then
    "$root/.beads/hooks/$name" "$@"
  fi
}
