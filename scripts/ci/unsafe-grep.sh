#!/usr/bin/env bash
# Text-level backstop for the Credo checks: fail on any use of raw (call, pipe without
# parens, capture, apply), {:safe, , String.to_atom (all forms) and keys: :atoms in lib/.
# It also covers ~H templates, which Credo does not parse.
# Usage: scripts/ci/unsafe-grep.sh [DIR]   (default: lib/ in the repository root)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
dir="${1:-lib/}"

# \braw\b has no legitimate use in lib/: it matches raw(, x |> raw, &raw/1,
# Phoenix.HTML.raw, :raw (apply). \bto_atom\b matches String.to_atom in every form.
pattern='\braw\b|\{:safe,|\bto_atom\b|keys: :atoms([^!]|$)'
rc=0
grep -rnE --include='*.ex' --include='*.exs' --include='*.heex' -e "$pattern" "$dir" || rc=$?
case "$rc" in
  0)
    echo "unsafe-grep: found raw / {:safe, / to_atom / keys: :atoms in $dir" >&2
    exit 1
    ;;
  1) ;;
  *)
    echo "unsafe-grep: grep failed (exit $rc); failing closed" >&2
    exit 1
    ;;
esac
echo "unsafe-grep: ok"
