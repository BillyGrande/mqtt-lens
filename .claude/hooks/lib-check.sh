#!/usr/bin/env bash
# PostToolUse (Edit/Write) check for files under lib/**. Exit 2 sends the message to Claude.
# Input (stdin JSON): tool_input.file_path (absolute path), cwd.
#
# Flags: raw(  {:safe,  String.to_atom  keys: :atoms
# The file is read from disk after the edit, so the check sees the final text.
# This is a fast text check. It does not replace Sobelow and Credo in make lint.
#
# Fail closed: unreadable input, or a lib/ file that cannot be read, exits 2.
set -u

fail() {
  echo "lib-check: $*" >&2
  exit 2
}

input="$(cat)"
f="$(jq -r '.tool_input.file_path // ""' <<<"$input" 2>/dev/null)" || fail "hook input is not valid JSON"
[ -n "$f" ] || exit 0

case "/$f" in
  */lib/*) ;;
  *) exit 0 ;;
esac

[ -r "$f" ] || fail "cannot read $f to check it"

found=0
# Each rule: label, then an extended regex.
scan() {
  local label="$1" re="$2" n line
  while IFS=: read -r n line; do
    [ -n "$n" ] || continue
    echo "lib-check: $f:$n: found $label:$line" >&2
    found=1
  done < <(grep -nE -- "$re" "$f" || true)
}

scan 'raw(' '(^|[^[:alnum:]_])raw\('
scan '{:safe,' '\{:safe[[:space:]]*,'
scan 'String.to_atom' 'String\.to_atom([^[:alnum:]_]|$)'
scan 'keys: :atoms' 'keys:[[:space:]]*:atoms'

if [ "$found" -eq 1 ]; then
  echo "lib-check: these patterns are not allowed in lib/ (XSS and atom-table risk). Fix them or explain why in the task." >&2
  exit 2
fi
exit 0
