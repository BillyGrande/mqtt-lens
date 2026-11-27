#!/usr/bin/env bash
# Runs every hook unit test, then smoke-checks the hook command lines in .claude/settings.json.
# Exit 0 only when all pass.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
settings="$root/.claude/settings.json"
fails=0

for t in "$root"/.claude/hooks/test/*_test.sh; do
  [ -e "$t" ] || continue
  if bash "$t" >/dev/null 2>&1; then
    echo "ok   $(basename "$t")"
  else
    echo "FAIL $(basename "$t")"
    fails=$((fails + 1))
  fi
done

# commands EVENT TOOL: print each hook command line whose matcher selects TOOL.
commands() {
  jq -r --arg ev "$1" --arg tool "$2" '
    (.hooks[$ev] // [])[]
    | select((.matcher // "") as $m | ($m == "") or ($tool | test("^(" + $m + ")$")))
    | .hooks[] | select(.type == "command") | .command' "$settings"
}

# run_hooks EVENT TOOL JSON: print exit codes, one per hook, space separated.
run_hooks() {
  local cmd out="" rc
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    printf '%s' "$3" | CLAUDE_PROJECT_DIR="$root" MQTTLENS_GH_LOGIN=BillyGrande bash -c "$cmd" >/dev/null 2>&1
    rc=$?
    out="$out $rc"
  done < <(commands "$1" "$2")
  echo "${out# }"
}

# smoke NAME EVENT TOOL JSON MODE
# MODE all0: every matching hook exits 0. MODE any2: at least one matching hook exits 2.
smoke() {
  local name="$1" codes ok=0 c
  codes="$(run_hooks "$2" "$3" "$4")"
  if [ -z "$codes" ]; then
    ok=1
  elif [ "$5" = all0 ]; then
    for c in $codes; do [ "$c" = 0 ] || ok=1; done
  else
    case " $codes " in *" 2 "*) ;; *) ok=1 ;; esac
  fi
  if [ "$ok" = 0 ]; then
    echo "ok   smoke: $name ($codes)"
  else
    echo "FAIL smoke: $name (exit codes: ${codes:-no hooks found})"
    fails=$((fails + 1))
  fi
}

jq -e . "$settings" >/dev/null 2>&1 || { echo "FAIL settings.json is not valid JSON"; fails=$((fails + 1)); }

smoke "Bash gh pr merge 1 blocked" PreToolUse Bash \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr merge 1\"},\"cwd\":\"$root\"}" any2
smoke "Bash ls allowed" PreToolUse Bash \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"$root\"}" all0
smoke "Read README.md allowed" PreToolUse Read \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$root/README.md\"},\"cwd\":\"$root\"}" all0
smoke "Read .env blocked" PreToolUse Read \
  "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$root/.env\"},\"cwd\":\"$root\"}" any2
smoke "Edit README.md (no agent_type) allowed" PreToolUse Edit \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$root/README.md\"},\"cwd\":\"$root\"}" all0

# Wiring checks: env, and each hook script is registered and executable.
for k in DO_NOT_TRACK DOLT_DISABLE_EVENT_FLUSH; do
  if [ "$(jq -r --arg k "$k" '.env[$k] // ""' "$settings")" = "1" ]; then
    echo "ok   env $k=1"
  else
    echo "FAIL env $k is not 1"
    fails=$((fails + 1))
  fi
done
for s in guard bash-policy read-policy lib-check require-result; do
  if ! grep -q "hooks/$s.sh" "$settings"; then
    echo "FAIL $s.sh is not in settings.json"
    fails=$((fails + 1))
  elif [ ! -x "$root/.claude/hooks/$s.sh" ]; then
    echo "FAIL $s.sh is not executable"
    fails=$((fails + 1))
  fi
done

if [ "$fails" -eq 0 ]; then
  echo "all hook checks passed"
  exit 0
fi
echo "$fails hook check(s) failed"
exit 1
