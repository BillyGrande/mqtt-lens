#!/usr/bin/env bash
# Tests for scripts/ci/sobelow-skips.sh using probe trees. Exit 0 when all pass.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../sobelow-skips.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

probe() { mkdir -p "$tmp/$1/lib" "$tmp/$1/config"; }
expect() { # expect NAME WANT_RC [GREP_PATTERN]
  local out rc
  out="$(SOBELOW_SKIPS_ROOT="$tmp/$1" bash "$script" 2>&1)"
  rc=$?
  if [ "$rc" -eq "$2" ] && { [ -z "${3:-}" ] || grep -q -- "$3" <<<"$out"; }; then
    echo "ok   $1"
  else
    echo "FAIL $1 (rc=$rc): $out"
    fails=$((fails + 1))
  fi
}

probe clean
printf 'defmodule A do\nend\n' >"$tmp/clean/lib/a.ex"
printf 'import Config\n' >"$tmp/clean/config/config.exs"
expect clean 0 'ok'

probe lib_skip
printf 'defmodule A do\n  # sobelow_skip ["Traversal.FileModule"]\n  def f, do: 1\nend\n' >"$tmp/lib_skip/lib/a.ex"
expect lib_skip 1 'lib/a.ex:2'

probe config_skip
printf 'import Config\n# sobelow_skip ["Config.Secrets"]\n' >"$tmp/config_skip/config/runtime.exs"
expect config_skip 1 'config/runtime.exs:2'

# Reviewer probe: a list with no check name spans lines and hides code.
probe multiline
printf 'defmodule P do\n  # sobelow_skip ["]\n  def run(cmd), do: System.cmd(cmd, [])\n  # "]\nend\n' >"$tmp/multiline/lib/probe.ex"
expect multiline 1 'lib/probe.ex:2'

probe skips_file
touch "$tmp/skips_file/.sobelow-skips"
expect skips_file 1 '.sobelow-skips'

[ "$fails" -eq 0 ]
