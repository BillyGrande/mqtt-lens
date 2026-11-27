#!/usr/bin/env bash
# Text-level backstop for the Credo checks: fail on raw( , {:safe, , String.to_atom
# and keys: :atoms in lib/. It also covers ~H templates, which Credo does not parse.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

pattern='(^|[^[:alnum:]_.])raw\(|\.raw\(|\{:safe,|String\.to_atom\(|keys: :atoms([^!]|$)'
rc=0
grep -rnE --include='*.ex' --include='*.exs' --include='*.heex' -e "$pattern" lib/ || rc=$?
case "$rc" in
  0)
    echo "unsafe-grep: found raw( / {:safe, / String.to_atom / keys: :atoms in lib/" >&2
    exit 1
    ;;
  1) ;;
  *)
    echo "unsafe-grep: grep failed (exit $rc); failing closed" >&2
    exit 1
    ;;
esac
echo "unsafe-grep: ok"
