#!/usr/bin/env bash
# Test-tamper gate. Usage: scripts/ci/test-tamper.sh BASE HEAD
# Reads the git repository of the CURRENT folder.
# A commit in BASE..HEAD with a line "Tests-Committed: <id>" freezes the files it added.
# A later commit without that trailer line must not change, delete or rename them.
# A later commit with the trailer (the test-author stage) may. A merge commit in the
# range fails. Fails closed on every git error. Prints paths and short SHAs only.
set -uo pipefail

fail() {
  echo "test-tamper: $*" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail "usage: test-tamper.sh BASE HEAD"

git rev-parse --git-dir > /dev/null 2>&1 || fail "not a git repository"
base="$(git rev-parse --verify --quiet "${1}^{commit}" 2> /dev/null)" || fail "BASE is not a commit"
head="$(git rev-parse --verify --quiet "${2}^{commit}" 2> /dev/null)" || fail "HEAD is not a commit"

merges="$(git rev-list --merges "${base}..${head}" 2> /dev/null)" || fail "cannot read the commit range"
if [ -n "$merges" ]; then
  while read -r sha; do
    echo "test-tamper: merge commit ${sha:0:7} in the range (rebase only)" >&2
  done <<< "$merges"
  exit 1
fi

commits="$(git rev-list --reverse "${base}..${head}" 2> /dev/null)" || fail "cannot read the commit range"

declare -A frozen=()
bad=0
have_trailer=0

while read -r sha; do
  [ -n "$sha" ] || continue
  short="${sha:0:7}"
  msg="$(git log -1 --format=%B "$sha" 2> /dev/null)" || fail "cannot read commit $short"
  # No rename detection: a rename shows as a delete of the old path and an add of the new.
  changed="$(git diff-tree --root --no-commit-id --no-renames -r --name-only "$sha" 2> /dev/null)" \
    || fail "cannot read the files of commit $short"

  if printf '%s\n' "$msg" | grep -Eq '^Tests-Committed: .+'; then
    have_trailer=1
    added="$(git diff-tree --root --no-commit-id --no-renames -r --name-only --diff-filter=A "$sha" 2> /dev/null)" \
      || fail "cannot read the files of commit $short"
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      [ -n "${frozen[$path]+x}" ] || frozen["$path"]="$short"
    done <<< "$added"
  else
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -n "${frozen[$path]+x}" ]; then
        echo "test-tamper: $path (frozen by ${frozen[$path]}) changed by commit $short" >&2
        bad=1
      fi
    done <<< "$changed"
  fi
done <<< "$commits"

[ "$bad" -eq 0 ] || exit 1
if [ "$have_trailer" -eq 0 ]; then
  echo "test-tamper: notice: no commit with a Tests-Committed trailer in ${base:0:7}..${head:0:7}, nothing to check"
else
  echo "test-tamper: ok"
fi
