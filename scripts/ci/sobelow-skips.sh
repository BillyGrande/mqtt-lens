#!/usr/bin/env bash
# Fail on any sobelow_skip comment in lib/** and config/*.exs that is not on the allow-list,
# and on any .sobelow-skips file. Usage: scripts/ci/sobelow-skips.sh
# Env (for tests): SOBELOW_SKIPS_ROOT (default: repo root), SOBELOW_SKIPS_ALLOW.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${SOBELOW_SKIPS_ROOT:-$(cd "$here/../.." && pwd)}"
allow="${SOBELOW_SKIPS_ALLOW:-$here/sobelow-skips.allow}"

if [ ! -r "$allow" ]; then
  echo "sobelow-skips: allow-list not readable: $allow" >&2
  exit 1
fi
cd "$root" || { echo "sobelow-skips: cannot cd to $root" >&2; exit 1; }

fails=0

# Any .sobelow-skips fingerprint file is forbidden.
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

# Every sobelow_skip comment in lib/** and config/*.exs (the files sobelow reads).
files=()
[ -d lib ] && files+=(lib)
if [ -d config ]; then
  for f in config/*.exs; do [ -e "$f" ] && files+=("$f"); done
fi
if [ "${#files[@]}" -gt 0 ]; then
  out="$(grep -rnH 'sobelow_skip' "${files[@]}")"
  rc=$?
  if [ "$rc" -ge 2 ]; then
    echo "sobelow-skips: grep failed (exit $rc)" >&2
    exit 1
  fi
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r line; do
      file="${line%%:*}"
      rest="${line#*:}"
      rest="${rest#*:}"
      # Exactly one skip per line, as a comment: "# sobelow_skip [..]" with
      # nothing but code before the "#" ignored by sobelow. More than one
      # skip on a line makes sobelow skip the whole file (and hides checks).
      count="$(printf '%s' "$rest" | grep -o 'sobelow_skip' | wc -l)"
      if [ "$count" -ne 1 ]; then
        echo "sobelow-skips: more than one sobelow_skip on a line in $file: $rest"
        fails=1
        continue
      fi
      list="$(printf '%s' "$rest" | sed -n 's/^[[:space:]]*#[[:space:]]*sobelow_skip[[:space:]]*\[\([^]]*\)\][[:space:]]*$/\1/p')"
      if [ -z "$list" ]; then
        echo "sobelow-skips: unparsable skip in $file (it must be a comment line alone): $rest"
        fails=1
        continue
      fi
      while IFS= read -r check; do
        check="$(printf '%s' "$check" | tr -d ' "')"
        [ -n "$check" ] || continue
        if ! grep -qxF "$file $check" "$allow"; then
          echo "sobelow-skips: not allowed: $file $check"
          fails=1
        fi
      done < <(printf '%s\n' "$list" | tr ',' '\n')
    done <<<"$out"
  fi
fi

[ "$fails" -eq 0 ] || exit 1
echo "sobelow-skips: ok"
