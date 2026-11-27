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

# scan_stream LABEL: read text on stdin, report hits, return 1 on any hit.
# Reports the line number of the deny-list entry, never the entry text or the matched text.
scan_stream() {
  local label="$1" text pat n=0 rc=0 g
  text="$(cat)"
  while IFS= read -r pat; do
    n=$((n + 1))
    [[ "$pat" =~ ^[[:space:]]*(#|$) ]] && continue
    # No pipe into grep -q: an early exit of grep would SIGPIPE the writer and, with
    # pipefail, turn a hit into "no hit" on input over the pipe buffer. Here-string only.
    # grep status: 0 = hit, 1 = no hit, anything else = error (fail closed).
    g=0
    grep -iqE -e "$pat" <<<"$text" 2>/dev/null || g=$?
    case "$g" in
      0)
        echo "guardrail: deny-list hit in $label: deny-list line $n" >&2
        rc=1
        ;;
      1) ;;
      *)
        echo "guardrail: deny-list line $n is not a valid regex (grep exit $g); failing closed" >&2
        rc=1
        ;;
    esac
  done < "$DENYLIST"
  return "$rc"
}

# scan_diff LABEL: read a unified diff on stdin, scan only added lines
# and report file + deny-list line number (never the entry text).
scan_diff() {
  local label="$1" file="" line rc=0 pat n g
  while IFS= read -r line; do
    case "$line" in
      "+++ b/"*) file="${line#+++ b/}" ;;
      "+++ "*) ;;
      "+"*)
        n=0
        while IFS= read -r pat; do
          n=$((n + 1))
          [[ "$pat" =~ ^[[:space:]]*(#|$) ]] && continue
          g=0
          grep -iqE -e "$pat" <<<"${line:1}" 2>/dev/null || g=$?
          case "$g" in
            0)
              echo "guardrail: deny-list hit in $label: file=${file:-?} deny-list line $n" >&2
              rc=1
              ;;
            1) ;;
            *)
              echo "guardrail: deny-list line $n is not a valid regex (grep exit $g); failing closed" >&2
              rc=1
              ;;
          esac
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
