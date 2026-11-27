#!/usr/bin/env bash
# shellcheck disable=SC2016
# Tests for bash-policy.sh, read-policy.sh, lib-check.sh, require-result.sh.
# Fixtures are JSON on stdin. bd and gh are PATH shims; the real ones are never called.
# Hook input fields used (Claude Code hooks docs): tool_name, tool_input.command,
# tool_input.file_path, cwd, transcript_path, agent_transcript_path, stop_hook_active,
# last_assistant_message.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/shims" "$TMP/home/.ssh" "$TMP/home/.config/gh" "$TMP/bd"
export STUB_LOG="$TMP/stub.log"
export BD_STUB_DIR="$TMP/bd"
: >"$STUB_LOG"

cat >"$TMP/shims/bd" <<'SH'
#!/usr/bin/env bash
echo "bd $*" >>"$STUB_LOG"
[ "${BD_STUB_FAIL:-}" = 1 ] && exit 1
if [ "${1:-}" = comments ]; then
  f="$BD_STUB_DIR/$2.json"
  if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi
  exit 0
fi
exit 0
SH
cat >"$TMP/shims/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >>"$STUB_LOG"
[ "${GH_STUB_FAIL:-}" = 1 ] && exit 1
if [ "${1:-}" = api ] && [ "${2:-}" = user ]; then
  echo "${GH_STUB_LOGIN:-}"
  exit 0
fi
exit 0
SH
chmod +x "$TMP/shims/bd" "$TMP/shims/gh"

export HOME="$TMP/home"
export PATH="$TMP/shims:$PATH"
export MQTTLENS_GH_LOGIN=BillyGrande

# Git repos (local only): one on main, one on a feature branch.
mkrepo() {
  git init -q -b "$2" "$1"
  git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
    commit -q --allow-empty -m init
}
MAINREPO="$TMP/mainrepo"
FEATREPO="$TMP/featrepo"
mkrepo "$MAINREPO" main
mkrepo "$FEATREPO" task/x

# Project dir for read-policy and lib-check.
PROJ="$TMP/proj"
mkdir -p "$PROJ/secrets" "$PROJ/lib/app" "$PROJ/test" "$PROJ/notes"
echo "K=v" >"$PROJ/.env"
echo "hi" >"$PROJ/README.md"
echo "x" >"$PROJ/notes/secrets.md"
ln -s "$PROJ/.env" "$PROJ/link.txt"

PASS=0
FAIL=0
RC=0
ERR=""

# run <script> <json> [env args...]
run() {
  local script="$1" json="$2"
  shift 2
  ERR="$(printf '%s' "$json" | env "$@" bash "$HOOKS/$script" 2>&1 >/dev/null)"
  RC=$?
}

# check <name> <want-rc> <stderr-pattern-or-empty> <script> <json> [env args...]
check() {
  local name="$1" want="$2" pat="$3"
  shift 3
  run "$@"
  if [ "$RC" -ne "$want" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (want rc=$want, got rc=$RC) $ERR" | head -3
    return
  fi
  if [ -n "$pat" ] && ! printf '%s' "$ERR" | grep -qF -- "$pat"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: $name (stderr lacks: $pat) got: $ERR" | head -3
    return
  fi
  PASS=$((PASS + 1))
  echo "ok:   $name"
}

bj() { jq -nc --arg c "$1" --arg d "${2:-$FEATREPO}" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}'; }
rj() { jq -nc --arg p "$1" --arg d "${2:-$PROJ}" \
  '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:$p},cwd:$d}'; }
wj() { jq -nc --arg p "$1" --arg t "${2:-Write}" --arg d "$PROJ" \
  '{hook_event_name:"PostToolUse",tool_name:$t,tool_input:{file_path:$p},cwd:$d}'; }

# ---------------------------------------------------------------- bash-policy.sh
B=bash-policy.sh
check "bp allow ls" 0 "" $B "$(bj 'ls -la')"
check "bp allow git status" 0 "" $B "$(bj 'git status')"
check "bp allow git commit" 0 "" $B "$(bj 'git commit -m docs' "$MAINREPO")"
check "bp block gh pr merge" 2 "" $B "$(bj 'gh pr merge 123')"
check "bp block gh pr merge flags" 2 "" $B "$(bj 'gh pr merge --squash --auto 5')"
check "bp block gh -R pr merge" 2 "" $B "$(bj 'gh -R o/r pr merge 5')"
check "bp block chained merge" 2 "" $B "$(bj 'echo hi && gh pr merge 1')"
check "bp block bash -c merge" 2 "" $B "$(bj "bash -c 'gh pr merge 1'")"
check "bp block gh api merge endpoint" 2 "" $B "$(bj 'gh api -X PUT repos/o/r/pulls/3/merge')"
check "bp block push origin main" 2 "" $B "$(bj 'git push origin main')"
check "bp block push origin master" 2 "" $B "$(bj 'git push origin master')"
check "bp block push HEAD:main" 2 "" $B "$(bj 'git push origin HEAD:main')"
check "bp block push --force" 2 "" $B "$(bj 'git push --force origin task/x')"
check "bp block push -f" 2 "" $B "$(bj 'git push -f origin task/x')"
check "bp block push --force-with-lease" 2 "" $B "$(bj 'git push --force-with-lease origin task/x')"
check "bp block push +refspec" 2 "" $B "$(bj 'git push origin +task/x')"
check "bp block push --all" 2 "" $B "$(bj 'git push --all origin')"
check "bp block push --tags" 2 "" $B "$(bj 'git push --tags origin')"
check "bp block push bare on main" 2 "" $B "$(bj 'git push' "$MAINREPO")"
check "bp block push origin HEAD on main" 2 "" $B "$(bj 'git push origin HEAD' "$MAINREPO")"
check "bp block git -C main repo push" 2 "" $B "$(bj "git -C $MAINREPO push")"
check "bp block sudo push main" 2 "" $B "$(bj 'sudo git push origin main')"
check "bp block abs-path git push main" 2 "" $B "$(bj '/usr/bin/git push origin main')"
check "bp block env-prefixed push main" 2 "" $B "$(bj 'FOO=1 git push origin main')"
check "bp allow push feature branch" 0 "" $B "$(bj 'git push -u origin task/ml-2p3.4')"
check "bp allow bare push on feature" 0 "" $B "$(bj 'git push')"
check "bp block reset --hard on main" 2 "" $B "$(bj 'git reset --hard HEAD~1' "$MAINREPO")"
check "bp allow reset --hard on feature" 0 "" $B "$(bj 'git reset --hard HEAD~1')"
check "bp allow reset --soft on main" 0 "" $B "$(bj 'git reset --soft HEAD~1' "$MAINREPO")"
check "bp block gh release" 2 "" $B "$(bj 'gh release create v1')"
check "bp block git tag create" 2 "" $B "$(bj 'git tag v1')"
check "bp block git tag annotated" 2 "" $B "$(bj 'git tag -a v1 -m x')"
check "bp allow git tag -l" 0 "" $B "$(bj 'git tag -l')"
check "bp block docker push" 2 "" $B "$(bj 'docker push ghcr.io/o/i:1')"
check "bp block podman push" 2 "" $B "$(bj 'podman push i:1')"
check "bp block buildx --push" 2 "" $B "$(bj 'docker buildx build --push -t i:1 .')"
check "bp account wrong via env" 2 "gh auth switch --user BillyGrande" $B "$(bj 'gh pr view 1')" MQTTLENS_GH_LOGIN=other
check "bp account ok via stub" 0 "" $B "$(bj 'gh pr view 1')" -u MQTTLENS_GH_LOGIN GH_STUB_LOGIN=BillyGrande
check "bp account wrong via stub" 2 "gh auth switch --user BillyGrande" $B "$(bj 'gh pr view 1')" -u MQTTLENS_GH_LOGIN GH_STUB_LOGIN=other
check "bp account lookup failure blocks" 2 "" $B "$(bj 'gh pr view 1')" -u MQTTLENS_GH_LOGIN GH_STUB_FAIL=1
check "bp account empty login blocks" 2 "" $B "$(bj 'gh pr view 1')" -u MQTTLENS_GH_LOGIN GH_STUB_LOGIN=
check "bp account wrong blocks push" 2 "gh auth switch --user BillyGrande" $B "$(bj 'git push -u origin task/x')" MQTTLENS_GH_LOGIN=other
check "bp gh auth switch exempt" 0 "" $B "$(bj 'gh auth switch --user BillyGrande')" MQTTLENS_GH_LOGIN=other
check "bp non-gh command skips account check" 0 "" $B "$(bj 'git status')" MQTTLENS_GH_LOGIN=other
check "bp empty command allowed" 0 "" $B "$(bj '')"
check "bp invalid json blocks" 2 "" $B 'not json{'
check "bp non-Bash tool ignored" 0 "" $B '{"tool_name":"Read","tool_input":{"file_path":"x"}}'

# ---------------------------------------------------------------- read-policy.sh
R=read-policy.sh
check "rp block Read .env" 2 "" $R "$(rj "$PROJ/.env")"
check "rp block Read .env.local" 2 "" $R "$(rj "$PROJ/.env.local")"
check "rp block Read relative .env" 2 "" $R "$(rj ".env")"
check "rp block Read pem" 2 "" $R "$(rj "$PROJ/server.pem")"
check "rp block Read key" 2 "" $R "$(rj "$PROJ/id.key")"
check "rp block Read secrets dir file" 2 "" $R "$(rj "$PROJ/secrets/token")"
check "rp block Read ssh" 2 "" $R "$(rj "$HOME/.ssh/id_ed25519")"
check "rp block Read gh config" 2 "" $R "$(rj "$HOME/.config/gh/hosts.yml")"
check "rp block Read via dotdot" 2 "" $R "$(rj "$HOME/x/../.ssh/id_rsa")"
check "rp block Read via symlink" 2 "" $R "$(rj "$PROJ/link.txt")"
check "rp allow Read README" 0 "" $R "$(rj "$PROJ/README.md")"
check "rp allow Read lib file" 0 "" $R "$(rj "$PROJ/lib/app/x.ex")"
check "rp allow Read secrets.md file" 0 "" $R "$(rj "$PROJ/notes/secrets.md")"
check "rp block Grep path secrets" 2 "" $R '{"tool_name":"Grep","tool_input":{"path":"secrets","pattern":"x"},"cwd":"'"$PROJ"'"}'
check "rp block Bash cat .env" 2 "" $R "$(bj 'cat .env' "$PROJ")"
check "rp block Bash cat < .env" 2 "" $R "$(bj 'cat < .env' "$PROJ")"
check "rp block Bash cat ~/.ssh" 2 "" $R "$(bj 'cat ~/.ssh/id_rsa' "$PROJ")"
check "rp block Bash cat HOME gh" 2 "" $R "$(bj 'cat $HOME/.config/gh/hosts.yml' "$PROJ")"
check "rp block Bash grep secrets" 2 "" $R "$(bj 'grep x secrets/a' "$PROJ")"
check "rp block Bash pem" 2 "" $R "$(bj 'openssl x509 -in foo.pem' "$PROJ")"
check "rp block Bash glob .e*" 2 "" $R "$(bj 'cat .e*' "$PROJ")"
check "rp block Bash --file=.env" 2 "" $R "$(bj 'tool --file=.env' "$PROJ")"
check "rp block Bash cd ssh" 2 "" $R "$(bj 'cd ~/.ssh && ls' "$PROJ")"
check "rp block Bash chained" 2 "" $R "$(bj 'echo a; cat .env' "$PROJ")"
check "rp allow Bash ls" 0 "" $R "$(bj 'ls -la' "$PROJ")"
check "rp allow Bash cat README" 0 "" $R "$(bj 'cat README.md' "$PROJ")"
check "rp allow Bash echo secretsauce" 0 "" $R "$(bj 'echo secretsauce' "$PROJ")"
check "rp invalid json blocks" 2 "" $R 'garbage'
check "rp allow Bash grep word secrets" 0 "" $R "$(bj 'grep -rn secrets specs/architecture/deployment.md' "$PROJ")"
check "rp allow Bash kubectl get secrets" 0 "" $R "$(bj 'kubectl get secrets -n app' "$PROJ")"
check "rp block Bash deploy/secrets path" 2 "" $R "$(bj 'cat deploy/secrets/example.yaml' "$PROJ")"
check "rp block Bash ls secrets/" 2 "" $R "$(bj 'ls secrets/' "$PROJ")"
check "rp block Bash ./secrets/a" 2 "" $R "$(bj 'cat ./secrets/a' "$PROJ")"
check "rp block Read relative secrets/a" 2 "" $R "$(rj 'secrets/a')"

# ---------------------------------------------------------------- lib-check.sh
L=lib-check.sh
put() { printf '%s\n' "$2" >"$PROJ/$1"; }
put lib/app/clean.ex 'defmodule Clean do def a, do: 1 end'
put lib/app/raw.ex 'def x(v), do: raw(v)'
put lib/app/safe.ex 'def x(v), do: {:safe, v}'
put lib/app/atom.ex 'def x(v), do: String.to_atom(v)'
put lib/app/existing.ex 'def x(v), do: String.to_existing_atom(v)'
put lib/app/keys.ex 'Jason.decode!(s, keys: :atoms)'
put test/raw_test.exs 'raw(x); String.to_atom(y)'
check "lc allow clean lib file" 0 "" $L "$(wj "$PROJ/lib/app/clean.ex")"
check "lc warn raw(" 2 "raw(" $L "$(wj "$PROJ/lib/app/raw.ex")"
check "lc warn {:safe," 2 "{:safe," $L "$(wj "$PROJ/lib/app/safe.ex")"
check "lc warn String.to_atom" 2 "String.to_atom" $L "$(wj "$PROJ/lib/app/atom.ex")"
check "lc warn keys: :atoms" 2 "keys: :atoms" $L "$(wj "$PROJ/lib/app/keys.ex")"
check "lc warn on Edit tool" 2 "" $L "$(wj "$PROJ/lib/app/raw.ex" Edit)"
check "lc message has line number" 2 ":1:" $L "$(wj "$PROJ/lib/app/raw.ex")"
check "lc allow to_existing_atom" 0 "" $L "$(wj "$PROJ/lib/app/existing.ex")"
check "lc ignore non-lib path" 0 "" $L "$(wj "$PROJ/test/raw_test.exs")"
check "lc missing lib file blocks" 2 "" $L "$(wj "$PROJ/lib/app/missing.ex")"
check "lc invalid json blocks" 2 "" $L '{{'

# ---------------------------------------------------------------- require-result.sh
Q=require-result.sh
mkdir -p "$TMP/tr"
assistant_line() { jq -nc --arg t "$1" \
  '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
handback_line() { jq -nc --arg t "$1" \
  '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:$t}}]}}'; }
sj() { jq -nc --arg m "$1" --argjson a "${2:-false}" \
  '{hook_event_name:"SubagentStop",stop_hook_active:$a,agent_type:"implementer",last_assistant_message:$m}'; }
printf '%s\n' '[{"id":"c1","issue_id":"t-1","author":"implementer","text":"RESULT: pass\nCommits: abc","created_at":"2026-01-01T00:00:00Z"}]' >"$BD_STUB_DIR/t-1.json"
printf '%s\n' '[{"id":"c2","issue_id":"t-2","author":"implementer","text":"tests-committed SHA: abc","created_at":"2026-01-01T00:00:00Z"}]' >"$BD_STUB_DIR/t-2.json"
printf '%s\n' '[{"id":"c3","issue_id":"t-3","author":"implementer","text":"see RESULT: pass later","created_at":"2026-01-01T00:00:00Z"}]' >"$BD_STUB_DIR/t-3.json"
printf '%s\n' '[{"id":"c4","issue_id":"t-4","author":"implementer","text":"result: pass","created_at":"2026-01-01T00:00:00Z"}]' >"$BD_STUB_DIR/t-4.json"
check "rr stop_hook_active allows" 0 "" $Q "$(sj $'done\nTASK: t-2' true)"
check "rr no TASK line allows" 0 "" $Q "$(sj 'All done, nothing to report.')"
check "rr TASK with RESULT allows" 0 "" $Q "$(sj $'summary\nTASK: t-1')"
check "rr TASK with no comments blocks" 2 "RESULT" $Q "$(sj $'summary\nTASK: t-9')"
check "rr TASK with non-RESULT comment blocks" 2 "" $Q "$(sj $'summary\nTASK: t-2')"
check "rr mid-text RESULT blocks" 2 "" $Q "$(sj $'summary\nTASK: t-3')"
check "rr lowercase result blocks" 2 "" $Q "$(sj $'summary\nTASK: t-4')"
check "rr last TASK wins (second has result)" 0 "" $Q "$(sj $'TASK: t-2\nmore\nTASK: t-1')"
check "rr last TASK wins (second lacks result)" 2 "" $Q "$(sj $'TASK: t-1\nmore\nTASK: t-2')"
check "rr bd failure blocks" 2 "" $Q "$(sj $'x\nTASK: t-1')" BD_STUB_FAIL=1
check "rr invalid json blocks" 2 "" $Q 'nope'
check "rr TASK without id allows" 0 "" $Q "$(sj 'TASK: ')"

assistant_line $'old\nTASK: t-1' >"$TMP/tr/agent_ok.jsonl"
assistant_line $'final\nTASK: t-2' >"$TMP/tr/agent_bad.jsonl"
{ assistant_line $'first\nTASK: t-2'; assistant_line 'closing remarks only'; } >"$TMP/tr/agent_split.jsonl"
handback_line $'report\nTASK: t-2' >"$TMP/tr/agent_handback.jsonl"
assistant_line 'no task here' >"$TMP/tr/agent_none.jsonl"
tj() { jq -nc --arg k "$1" --arg p "$2" \
  '{hook_event_name:"SubagentStop",stop_hook_active:false} | .[$k]=$p'; }
check "rr transcript_path with RESULT allows" 0 "" $Q "$(tj transcript_path "$TMP/tr/agent_ok.jsonl")"
check "rr transcript_path without RESULT blocks" 2 "" $Q "$(tj transcript_path "$TMP/tr/agent_bad.jsonl")"
check "rr agent_transcript_path without RESULT blocks" 2 "" $Q "$(tj agent_transcript_path "$TMP/tr/agent_bad.jsonl")"
check "rr transcript last message used only" 0 "" $Q "$(tj transcript_path "$TMP/tr/agent_split.jsonl")"
check "rr transcript handback message read" 2 "" $Q "$(tj transcript_path "$TMP/tr/agent_handback.jsonl")"
check "rr transcript without TASK allows" 0 "" $Q "$(tj transcript_path "$TMP/tr/agent_none.jsonl")"
check "rr unreadable transcript and no message blocks" 2 "" $Q "$(tj transcript_path "$TMP/tr/missing.jsonl")"
check "rr no message and no transcript blocks" 2 "" $Q '{"hook_event_name":"SubagentStop","stop_hook_active":false}'

# Safety: tests must never reach the real gh or bd. Shims log every call.
if grep -q '^bd comments .*;' "$STUB_LOG"; then
  FAIL=$((FAIL + 1))
  echo "FAIL: bd received unsanitised id"
else
  PASS=$((PASS + 1))
  echo "ok:   bd never received unsanitised id"
fi

echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] && [ "$PASS" -ge 25 ]
