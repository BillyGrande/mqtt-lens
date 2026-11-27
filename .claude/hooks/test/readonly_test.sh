#!/usr/bin/env bash
# Tests for readonly-check.sh (SubagentStart snapshot, SubagentStop compare).
# Hook input fields used (Claude Code hooks docs): hook_event_name, agent_id, agent_type,
# cwd, stop_hook_active. Uses a temporary local git repo as cwd.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$(cd "$HERE/.." && pwd)/readonly-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

fails=0
pass=0
G=(git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false)

mkrepo() {
  rm -rf "$TMP/repo" "$TMP/wt"
  git init -q -b main "$TMP/repo"
  echo one >"$TMP/repo/a.txt"
  git -C "$TMP/repo" add a.txt
  "${G[@]}" -C "$TMP/repo" commit -q -m init
}

# ev EVENT ROLE ID [ACTIVE] [CWD]: hook input JSON.
ev() {
  jq -n --arg e "$1" --arg r "$2" --arg i "$3" --arg c "${5:-$TMP/repo}" --argjson a "${4:-false}" \
    '{hook_event_name:$e, agent_type:$r, agent_id:$i, cwd:$c, stop_hook_active:$a}'
}

# run JSON: sets rc and err.
run() {
  err="$(printf '%s' "$1" | bash "$HOOK" 2>&1 >/dev/null)"
  rc=$?
}

# expect NAME WANT_RC [GREP_ERR]
expect() {
  if [ "$rc" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$err" | grep -q -- "$3"; }; then
    pass=$((pass + 1))
  else
    echo "FAIL $1 (rc=$rc want $2; stderr: $err)"
    fails=$((fails + 1))
  fi
}

for role in verifier reviewer security-reviewer scout; do
  mkrepo
  run "$(ev SubagentStart "$role" "id-$role")"
  expect "$role start" 0
  run "$(ev SubagentStop "$role" "id-$role")"
  expect "$role clean stop allowed" 0
done

mkrepo
run "$(ev SubagentStart verifier v1)"
expect "start ok" 0
echo two >>"$TMP/repo/a.txt"
run "$(ev SubagentStop verifier v1)"
expect "modified tracked file blocked" 2 "a.txt"

mkrepo
run "$(ev SubagentStart reviewer r1)"
echo x >"$TMP/repo/new-file.txt"
run "$(ev SubagentStop reviewer r1)"
expect "new untracked file blocked" 2 "new-file.txt"

mkrepo
run "$(ev SubagentStart scout s1)"
mkdir -p "$TMP/repo/sub"
echo x >"$TMP/repo/sub/deep.txt"
run "$(ev SubagentStop scout s1)"
expect "new file in new dir named" 2 "sub/deep.txt"

mkrepo
run "$(ev SubagentStart security-reviewer c1)"
"${G[@]}" -C "$TMP/repo" commit -q --allow-empty -m sneaky
run "$(ev SubagentStop security-reviewer c1)"
expect "new commit blocked" 2

mkrepo
run "$(ev SubagentStart verifier k1)"
echo two >>"$TMP/repo/a.txt"
"${G[@]}" -C "$TMP/repo" commit -q -am change
run "$(ev SubagentStop verifier k1)"
expect "commit of a tracked change blocked" 2

# A checkout of an existing branch is not a change: the verifier must check out the task branch.
mkrepo
git -C "$TMP/repo" branch task/x
run "$(ev SubagentStart verifier k2)"
git -C "$TMP/repo" checkout -q task/x
run "$(ev SubagentStop verifier k2)"
expect "branch checkout allowed" 0

# Pre-existing dirt that does not change is allowed.
mkrepo
echo pre >"$TMP/repo/pre.txt"
run "$(ev SubagentStart verifier d1)"
run "$(ev SubagentStop verifier d1)"
expect "unchanged dirty tree allowed" 0

# Other roles: always allowed, even with changes and no snapshot.
mkrepo
run "$(ev SubagentStart implementer w1)"
expect "writer start" 0
echo two >>"$TMP/repo/a.txt"
"${G[@]}" -C "$TMP/repo" commit -q -am change
run "$(ev SubagentStop implementer w1)"
expect "implementer stop allowed" 0
run "$(ev SubagentStop Explore w2)"
expect "other type without snapshot allowed" 0
run "$(printf '{"hook_event_name":"SubagentStop","agent_id":"w3","cwd":"%s"}' "$TMP/repo")"
expect "no agent_type allowed" 0

# stop_hook_active allowed.
mkrepo
run "$(ev SubagentStart verifier a1)"
echo two >>"$TMP/repo/a.txt"
run "$(ev SubagentStop verifier a1 true)"
expect "stop_hook_active allowed" 0

# Missing snapshot for a read-only role: block.
mkrepo
run "$(ev SubagentStop verifier none1)"
expect "missing snapshot blocked" 2 "snapshot"

# Bad JSON: block.
run "not json"
expect "bad JSON blocked" 2
run ""
expect "empty input blocked" 2

# Unsafe agent_id must not escape the snapshot dir.
mkrepo
run "$(ev SubagentStart verifier '../../evil')"
run "$(ev SubagentStop verifier '../../evil')"
if [ -e "$TMP/evil" ] || [ -e "$TMP/repo/.git/evil" ]; then
  echo "FAIL unsafe agent_id escaped"
  fails=$((fails + 1))
else
  pass=$((pass + 1))
fi

# Clean stop deletes the snapshot.
mkrepo
run "$(ev SubagentStart verifier del1)"
run "$(ev SubagentStop verifier del1)"
if [ -n "$(ls -A "$TMP/repo/.git/mqtt-lens-ro" 2>/dev/null)" ]; then
  echo "FAIL snapshot not deleted"
  fails=$((fails + 1))
else
  pass=$((pass + 1))
fi

# Linked worktree cwd: snapshot goes to the common git dir and compare works.
mkrepo
git -C "$TMP/repo" worktree add -q -b wt "$TMP/wt"
run "$(ev SubagentStart verifier wt1 false "$TMP/wt")"
expect "worktree start" 0
echo y >"$TMP/wt/z.txt"
run "$(ev SubagentStop verifier wt1 false "$TMP/wt")"
expect "worktree new file blocked" 2 "z.txt"

if [ "$fails" -eq 0 ]; then
  echo "readonly_test: $pass passed"
  exit 0
fi
echo "readonly_test: $fails failed"
exit 1
