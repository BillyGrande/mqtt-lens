#!/usr/bin/env bash
# Fail on any "sobelow_skip" text in lib/ or config/, and on any .sobelow-skips
# file. Fail closed on grep or find errors. Usage: scripts/ci/sobelow-skips.sh
# Env (for tests): SOBELOW_SKIPS_ROOT (default: repo root).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${SOBELOW_SKIPS_ROOT:-$(cd "$here/../.." && pwd)}"
cd "$root" || { echo "sobelow-skips: cannot cd to $root" >&2; exit 1; }

fails=0

found="$(find . \( -path ./deps -o -path ./_build -o -path ./node_modules -o -path ./.git \) -prune -o -name .sobelow-skips -print 2>&1)"
if [ $? -ne 0 ]; then
  echo "sobelow-skips: find failed: $found" >&2
  exit 1
fi
if [ -n "$found" ]; then
  while IFS= read -r f; do
    echo "sobelow-skips: forbidden file: ${f#./}"
  done <<<"$found"
  fails=1
fi

dirs=()
for d in lib config; do [ -d "$d" ] && dirs+=("$d"); done
if [ "${#dirs[@]}" -gt 0 ]; then
  out="$(grep -rnH 'sobelow_skip' "${dirs[@]}")"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "sobelow-skips: grep failed (exit $rc)" >&2
    exit 1
  fi
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r line; do
      file="${line%%:*}"
      rest="${line#*:}"
      echo "sobelow-skips: forbidden sobelow_skip at $file:${rest%%:*}"
    done <<<"$out"
    fails=1
  fi
fi

[ "$fails" -eq 0 ] || exit 1
echo "sobelow-skips: ok"
