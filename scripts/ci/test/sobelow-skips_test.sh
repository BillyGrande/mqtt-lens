#!/usr/bin/env bash
# Tests for scripts/ci/sobelow-skips.sh using probe trees. Exit 0 when all pass.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../sobelow-skips.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

probe() { # probe NAME: fresh tree in $tmp/NAME with an allow-list
  mkdir -p "$tmp/$1/lib"
  printf 'lib/a.ex Traversal.FileModule\n' >"$tmp/$1.allow"
}
run() { SOBELOW_SKIPS_ROOT="$tmp/$1" SOBELOW_SKIPS_ALLOW="$tmp/$1.allow" bash "$script" 2>&1; }
expect() { # expect NAME WANT_RC [GREP_PATTERN]
  local out rc
  out="$(run "$1")"
  rc=$?
  if [ "$rc" -eq "$2" ] && { [ -z "${3:-}" ] || grep -q -- "$3" <<<"$out"; }; then
    echo "ok   $1"
  else
    echo "FAIL $1 (rc=$rc): $out"
    fails=$((fails + 1))
  fi
}

probe allowed
printf '  # sobelow_skip ["Traversal.FileModule"]\n  def f, do: 1\n' >"$tmp/allowed/lib/a.ex"
expect allowed 0

probe none
printf 'defmodule A do\nend\n' >"$tmp/none/lib/a.ex"
expect none 0

probe extra_check
printf '# sobelow_skip ["Traversal.FileModule", "Config"]\n' >"$tmp/extra_check/lib/a.ex"
expect extra_check 1 'lib/a.ex Config'

probe extra_file
printf '# sobelow_skip ["Traversal.FileModule"]\n' >"$tmp/extra_file/lib/b.ex"
expect extra_file 1 'lib/b.ex Traversal.FileModule'

probe skips_file
touch "$tmp/skips_file/.sobelow-skips"
expect skips_file 1 '.sobelow-skips'

probe nested_skips_file
mkdir -p "$tmp/nested_skips_file/priv"
touch "$tmp/nested_skips_file/priv/.sobelow-skips"
expect nested_skips_file 1 'priv/.sobelow-skips'

probe no_allow
rm "$tmp/no_allow.allow"
expect no_allow 1 'allow-list'

[ "$fails" -eq 0 ]
