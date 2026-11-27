#!/usr/bin/env bash
# Tests for .claude/hooks/guard.sh: pipe JSON fixtures, check exit codes.
# Exit 0 = allow, exit 2 = block.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="$here/../guard.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
repo="$work/repo"
outside="$work/outside"
mkdir -p "$repo" "$outside"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# Fixture repo: main, then a task branch with a tests commit (trailer) and an impl commit.
git -C "$repo" init -q -b main
mkdir -p "$repo/specs" "$repo/lib" "$repo/test"
echo base >"$repo/README.md"
git -C "$repo" add -A
git -C "$repo" commit -q -m "base"
git -C "$repo" checkout -q -b task/ml-test
echo t >"$repo/test/foo_test.exs"
git -C "$repo" add -A
git -C "$repo" commit -q -m "tests first

Tests-Committed: ml-test"
echo i >"$repo/lib/impl.ex"
git -C "$repo" add -A
git -C "$repo" commit -q -m "impl"
ln -s "$outside" "$repo/specs/escape"

pass=0
fail=0

# check NAME EXPECTED_EXIT JSON
check() {
  local name="$1" want="$2" json="$3" got
  printf '%s' "$json" | bash "$guard" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (want $want, got $got)"
  fi
}

# edit ROLE TOOL PATH [CWD]
edit() {
  local role="$1" tool="$2" path="$3" cwd="${4:-$repo}"
  if [ -n "$role" ]; then
    jq -nc --arg r "$role" --arg t "$tool" --arg p "$path" --arg c "$cwd" \
      '{agent_type:$r,tool_name:$t,cwd:$c,tool_input:(if $t=="NotebookEdit" then {notebook_path:$p} else {file_path:$p} end)}'
  else
    jq -nc --arg t "$tool" --arg p "$path" --arg c "$cwd" \
      '{tool_name:$t,cwd:$c,tool_input:{file_path:$p}}'
  fi
}

# bashj ROLE COMMAND
bashj() {
  jq -nc --arg r "$1" --arg c "$2" --arg d "$repo" \
    '{agent_type:$r,tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'
}

# --- No role / unknown role: allow
check "main session writes anywhere" 0 "$(edit "" Write "$repo/lib/a.ex")"
check "main session writes specs" 0 "$(edit "" Edit "specs/a.md")"
check "unknown agent_type allowed" 0 "$(edit "mystery" Write "lib/a.ex")"

# --- architect / spec-keeper: specs/** only
check "architect writes specs" 0 "$(edit architect Write specs/a.md)"
check "architect writes nested specs" 0 "$(edit architect Edit specs/process/b.md)"
check "architect absolute path in root" 0 "$(edit architect Write "$repo/specs/a.md")"
check "architect blocked from lib" 2 "$(edit architect Write lib/a.ex)"
check "architect blocked from root file" 2 "$(edit architect Write README.md)"
check "spec-keeper writes specs" 0 "$(edit spec-keeper Edit specs/a.md)"
check "spec-keeper blocked from test" 2 "$(edit spec-keeper Write test/a.exs)"

# --- test-author / implementer: lib test assets config priv
for d in lib test assets config priv; do
  check "test-author writes $d" 0 "$(edit test-author Write "$d/x.txt")"
  check "implementer writes $d" 0 "$(edit implementer Write "$d/x.txt")"
done
check "test-author blocked from specs" 2 "$(edit test-author Write specs/a.md)"
check "implementer blocked from specs" 2 "$(edit implementer Edit specs/a.md)"
check "implementer blocked from hooks" 2 "$(edit implementer Write .claude/hooks/guard.sh)"
check "implementer blocked from settings" 2 "$(edit implementer Write .claude/settings.json)"
check "prefix confusion libx" 2 "$(edit implementer Write libx/a.ex)"
check "bare dir name without file" 2 "$(edit implementer Write lib)"
check "implementer MultiEdit lib" 0 "$(edit implementer MultiEdit lib/a.ex)"
check "implementer NotebookEdit test" 0 "$(edit implementer NotebookEdit test/n.ipynb)"
check "implementer NotebookEdit specs" 2 "$(edit implementer NotebookEdit specs/n.ipynb)"
check "implementer Write without path" 2 "$(jq -nc --arg c "$repo" '{agent_type:"implementer",tool_name:"Write",cwd:$c,tool_input:{}}')"

# --- Path attacks
check "traversal out of specs" 2 "$(edit architect Write specs/../lib/a.ex)"
check "traversal out of repo" 2 "$(edit implementer Write lib/../../outside/a)"
check "traversal even if it lands inside" 2 "$(edit implementer Write lib/../lib/a.ex)"
check "absolute outside root" 2 "$(edit implementer Write /etc/passwd)"
check "absolute sibling prefix of root" 2 "$(edit implementer Write "$repo-evil/lib/a.ex")"
check "symlink escape" 2 "$(edit architect Write specs/escape/x.md)"
check "dot segment normalised" 0 "$(edit implementer Write ./lib/./a.ex)"
check "cwd not a git repo" 2 "$(edit implementer Write lib/a.ex "$outside")"
check "absolute path from subdir cwd" 0 "$(edit implementer Write "$repo/lib/a.ex" "$repo/lib")"

# --- No-write roles
for r in verifier reviewer security-reviewer scout orchestrator; do
  check "$r blocked from Write" 2 "$(edit "$r" Write lib/a.ex)"
  check "$r blocked from Edit specs" 2 "$(edit "$r" Edit specs/a.md)"
done
check "verifier can read" 0 "$(edit verifier Read lib/a.ex)"
check "verifier can run Bash" 0 "$(bashj verifier "make check")"
check "implementer can run Bash" 0 "$(bashj implementer "mix test")"

# --- Fail closed on bad input
check "bad JSON blocked" 2 "not json{"
check "empty input blocked" 2 ""
check "non-string agent_type blocked" 2 '{"agent_type":5,"tool_name":"Write","tool_input":{"file_path":"lib/a"}}'

# --- Orchestrator Bash allow-list
for c in "bd ready --json" "bd show ml-1" "git status" "git log --oneline" "git worktree list" \
  "git worktree remove /tmp/wt" "gh pr view 3" "gh pr list" "gh pr checks 3" "  bd ready"; do
  check "orchestrator allows: $c" 0 "$(bashj orchestrator "$c")"
done
for c in "git push" "rm -rf x" "gh pr merge 3" "git worktree add x" "ls" "bdx ready" "git statusx" "" \
  "bd ready; rm x" "bd ready && rm x" "bd ready || rm x" "bd ready | sh" 'bd ready `id`' \
  'bd ready $(id)' "bd ready > f" "bd ready < f" "git status & rm x" $'bd ready\nrm x' 'bd show $HOME'; do
  check "orchestrator blocks: $c" 2 "$(bashj orchestrator "$c")"
done
check "orchestrator Bash without command" 2 "$(jq -nc --arg d "$repo" '{agent_type:"orchestrator",tool_name:"Bash",cwd:$d,tool_input:{}}')"

# --- Test-tamper (implementer only)
check "tamper: implementer edits committed test" 2 "$(edit implementer Edit test/foo_test.exs)"
check "tamper: absolute path" 2 "$(edit implementer Edit "$repo/test/foo_test.exs")"
check "tamper: dot segment path" 2 "$(edit implementer Edit test/./foo_test.exs)"
check "tamper: other test file allowed" 0 "$(edit implementer Write test/other_test.exs)"
check "tamper: impl file added without trailer allowed" 0 "$(edit implementer Edit lib/impl.ex)"
check "tamper: test-author may edit its own test" 0 "$(edit test-author Edit test/foo_test.exs)"

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ] && [ "$pass" -ge 20 ]
