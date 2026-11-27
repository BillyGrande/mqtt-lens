#!/usr/bin/env bash
# Test-tamper gate. Usage: scripts/ci/test-tamper.sh BASE HEAD
# Reads the git repository of the CURRENT folder. Fails in a shallow repository.
# A commit counts as a tests commit only when it has a real git trailer
# "Tests-Committed: <id>" (git trailer parse) and <id> is one token with no white space
# (the same pattern as .claude/hooks/guard.sh).
# Rules for BASE..HEAD (a merge commit in the range fails):
#   - Before the first tests commit, a commit without the trailer must not change a path
#     under test/.
#   - After the first tests commit, a commit without the trailer must not add, change,
#     delete, rename or change the mode of a path under test/ or config/test.exs.
#   - The files that a tests commit added stay frozen for later commits without the trailer.
#   - A range with no tests commit that changes a path under lib/ fails.
# A later commit with the trailer (the test-author stage) may change these paths.
# Fails closed on every git error. Prints paths and short SHAs only.
set -uo pipefail

fail() {
  echo "test-tamper: $*" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail "usage: test-tamper.sh BASE HEAD"

git rev-parse --git-dir > /dev/null 2>&1 || fail "not a git repository"
shallow="$(git rev-parse --is-shallow-repository 2> /dev/null)" || fail "cannot read the shallow state"
case "$shallow" in
  false) ;;
  true) fail "shallow repository: the history is incomplete (fetch the full history)" ;;
  *) fail "unexpected shallow state" ;;
esac
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
lib_changed=0

# A path that a commit without the trailer must not change. Before the first tests
# commit: test/ only. After it: test/ and config/test.exs.
is_test_path() {
  case "$1" in
    test/*) return 0 ;;
    config/test.exs) [ "$have_trailer" -eq 1 ] && return 0 ;;
  esac
  return 1
}

while read -r sha; do
  [ -n "$sha" ] || continue
  short="${sha:0:7}"
  values="$(git log -1 --format='%(trailers:key=Tests-Committed,valueonly)' "$sha" 2> /dev/null)" \
    || fail "cannot read commit $short"
  # No rename detection: a rename shows as a delete of the old path and an add of the new.
  changed="$(git diff-tree --root --no-commit-id --no-renames -r --name-only "$sha" 2> /dev/null)" \
    || fail "cannot read the files of commit $short"

  if printf '%s\n' "$values" | grep -Eq '^[^[:space:]]+[[:space:]]*$'; then
    added="$(git diff-tree --root --no-commit-id --no-renames -r --name-only --diff-filter=A "$sha" 2> /dev/null)" \
      || fail "cannot read the files of commit $short"
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      [ -n "${frozen[$path]+x}" ] || frozen["$path"]="$short"
    done <<< "$added"
    have_trailer=1
  else
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -n "${frozen[$path]+x}" ]; then
        echo "test-tamper: $path (frozen by ${frozen[$path]}) changed by commit $short" >&2
        bad=1
      elif is_test_path "$path"; then
        echo "test-tamper: $path changed by commit $short without a Tests-Committed trailer" >&2
        bad=1
      fi
    done <<< "$changed"
  fi
  # Paths under lib/ in a range that has no tests commit (so far).
  if [ "$have_trailer" -eq 0 ]; then
    while IFS= read -r path; do
      case "$path" in
        lib/*) lib_changed=1 ;;
      esac
    done <<< "$changed"
  fi
done <<< "$commits"

if [ "$have_trailer" -eq 0 ] && [ "$lib_changed" -eq 1 ]; then
  echo "test-tamper: no commit with a Tests-Committed trailer in ${base:0:7}..${head:0:7}, but the range changes lib/" >&2
  bad=1
fi
[ "$bad" -eq 0 ] || exit 1
if [ "$have_trailer" -eq 0 ]; then
  echo "test-tamper: notice: no commit with a Tests-Committed trailer in ${base:0:7}..${head:0:7}, nothing to check"
else
  echo "test-tamper: ok"
fi
