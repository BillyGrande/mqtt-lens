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

# Bypass 1: a comment inside a keyword list in a config file (sobelow then
# skips the whole file as unparsable).
probe config_comment
mkdir -p "$tmp/config_comment/config"
printf 'import Config\n\nconfig :a, B,\n  # sobelow_skip ["Config.Secrets"]\n  secret_key_base: "x"\n' >"$tmp/config_comment/config/runtime.exs"
expect config_comment 1 'config/runtime.exs Config.Secrets'

# Bypass 2: the allowed check name placed inside a call, not above a def.
# The script accepts the comment (file + check are on the allow-list), so
# sobelow --strict must fail on the unparsable file.
probe allowed_elsewhere
printf 'defmodule A do\n  def f(cmd), do: System.cmd(cmd, [\n  # sobelow_skip ["Traversal.FileModule"]\n  "-v"])\nend\n' >"$tmp/allowed_elsewhere/lib/a.ex"
expect allowed_elsewhere 0
if command -v mix >/dev/null 2>&1 && [ -f "$here/../../../mix.exs" ]; then
  repo="$(cd "$here/../../.." && pwd)"
  mkdir -p "$tmp/allowed_elsewhere/config"
  cp "$repo/mix.exs" "$repo/.sobelow-conf" "$tmp/allowed_elsewhere/"
  cp "$repo/config/config.exs" "$tmp/allowed_elsewhere/config/"
  if (cd "$repo" && mix sobelow --root "$tmp/allowed_elsewhere" --exit --threshold low --strict >"$tmp/sobelow.out" 2>&1); then
    echo "FAIL allowed_elsewhere_strict: sobelow --strict exit 0: $(tail -3 "$tmp/sobelow.out")"
    fails=$((fails + 1))
  else
    echo "ok   allowed_elsewhere_strict"
  fi
fi

# Bypass 3: two skip comments on one line (the script read only the last).
probe two_on_line
printf '# sobelow_skip ["CI.System"] # sobelow_skip ["Traversal.FileModule"]\ndef f(cmd), do: System.cmd(cmd, [])\n' >"$tmp/two_on_line/lib/a.ex"
expect two_on_line 1 'more than one'

probe no_allow
rm "$tmp/no_allow.allow"
expect no_allow 1 'allow-list'

[ "$fails" -eq 0 ]
