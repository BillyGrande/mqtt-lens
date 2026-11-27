#!/usr/bin/env bash
# Dry-run test for priv/dry_run/hello.sh (throw-away, removed in M2).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../../priv/dry_run/hello.sh"
fail=0

if [ ! -f "$script" ]; then
  echo "FAIL: $script does not exist"
  exit 1
fi

out="$(bash "$script")"
code=$?

[ "$out" = "mqtt-lens ok" ] || { echo "FAIL: output was '$out'"; fail=1; }
[ "$code" -eq 0 ] || { echo "FAIL: exit code $code"; fail=1; }
[ "$(bash "$script" | wc -l)" -eq 1 ] || { echo "FAIL: output is not exactly one line"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS"
exit "$fail"
