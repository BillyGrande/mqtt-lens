#!/usr/bin/env bash
# SubagentStop hook: block the stop (exit 2) until the task has a RESULT: comment.
# Input (stdin JSON, per the Claude Code hooks docs): stop_hook_active,
# last_assistant_message, agent_transcript_path, transcript_path.
#   - stop_hook_active=true: allow (avoids a stop loop).
#   - The task ID comes from the last "TASK: <id>" in the last assistant message.
#     Source order: last_assistant_message; then the last assistant entry of
#     agent_transcript_path (the subagent's own transcript); with no
#     last_assistant_message and no agent_transcript_path, transcript_path.
#     The docs say transcript_path is the MAIN session transcript, so it is the last
#     resort and is never used when last_assistant_message exists.
#   - No TASK line: allow (non-task agents).
#   - Else bd comments <id> --json must hold a comment whose text starts with RESULT:
#
# Fail closed: invalid input, no readable source, and a failed bd call all block.
# Transcript line format (type=assistant, message.content[] text and SubagentHandback
# tool_use input.message) is an assumption: not confirmed in the docs.
# shellcheck disable=SC2088
set -u

block() {
  echo "require-result: $*" >&2
  exit 2
}

input="$(cat)"
active="$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null)" || block "hook input is not valid JSON"
[ "$active" = "true" ] && exit 0

msg="$(jq -r '.last_assistant_message // ""' <<<"$input")"
atp="$(jq -r '.agent_transcript_path // ""' <<<"$input")"
tp="$(jq -r '.transcript_path // ""' <<<"$input")"

expand() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Text of the last assistant entry in a JSONL transcript.
last_text() {
  jq -Rrs '
    split("\n")
    | map(fromjson? // empty)
    | map(select(type == "object" and .type == "assistant")
        | [ .message.content
            | if type == "array" then .[]
                | (select(.type == "text") | .text),
                  (select(.type == "tool_use" and .name == "SubagentHandback") | .input.message)
              else . end ]
        | map(select(type == "string"))
        | join("\n"))
    | map(select(length > 0))
    | last // ""' "$1"
}

task_id() {
  printf '%s\n' "$1" | grep -oE 'TASK:[[:space:]]*[A-Za-z0-9][A-Za-z0-9._-]*' | tail -n 1 |
    sed -E 's/^TASK:[[:space:]]*//; s/[._-]+$//'
}

id=""
if [ -n "$msg" ]; then
  id="$(task_id "$msg")"
  if [ -z "$id" ] && [ -n "$atp" ]; then
    f="$(expand "$atp")"
    if [ -r "$f" ]; then
      id="$(task_id "$(last_text "$f")")"
    fi
  fi
else
  src="${atp:-$tp}"
  [ -n "$src" ] || block "no last_assistant_message and no transcript path: cannot find the task. Report with a TASK: <id> line."
  f="$(expand "$src")"
  [ -r "$f" ] || block "cannot read transcript $f: cannot find the task."
  id="$(task_id "$(last_text "$f")")"
fi

[ -n "$id" ] || exit 0

comments="$(bd comments "$id" --json 2>/dev/null)" || block "bd comments $id failed. Cannot confirm a RESULT: comment."
if jq -e 'type == "array" and any(.[]; ((.text // "") | test("\\A\\s*RESULT:")))' <<<"$comments" >/dev/null 2>&1; then
  exit 0
fi
block "task $id has no RESULT: comment. Add it with: bd comment $id --stdin (first line RESULT: pass or RESULT: fail), then stop again."
