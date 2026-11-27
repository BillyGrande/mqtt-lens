#!/usr/bin/env bash
# SubagentStart and SubagentStop hook: the read-only roles must not change the repo.
# Roles: verifier, reviewer, security-reviewer, scout. Other agent types are never blocked.
# Input (stdin JSON, per the Claude Code hooks docs): hook_event_name, agent_type,
# agent_id, cwd, stop_hook_active.
#   - SubagentStart: save a snapshot (HEAD, git status --porcelain=v1 -uall, HEAD reflog
#     length) to <git-common-dir>/mqtt-lens-ro/<agent_id>. SubagentStart cannot block.
#   - SubagentStop: compare. Block (exit 2) and name the changed paths when the status
#     differs or when a new commit exists. A checkout that only moves HEAD is allowed
#     (the verifier checks out the task branch). Delete the snapshot on a clean stop.
#   - stop_hook_active=true: allow (avoids a stop loop).
#
# Fail closed for the read-only roles: bad JSON, a missing snapshot, an unreadable repo
# and an unreadable reflog all block. Other roles are never blocked.
set -u

block() {
  echo "readonly-check: $*" >&2
  exit 2
}

input="$(cat)"
jq -e 'type == "object"' <<<"$input" >/dev/null 2>&1 || block "hook input is not valid JSON. Cannot check the role."

field() { jq -r --arg k "$1" '.[$k] // "" | if type == "string" then . else tojson end' <<<"$input"; }

role="$(field agent_type)"
case "$role" in
  verifier | reviewer | security-reviewer | scout) ;;
  *) exit 0 ;;
esac

event="$(field hook_event_name)"
id="$(field agent_id)"
cwd="$(field cwd)"
active="$(field stop_hook_active)"

[ -n "$id" ] || block "read-only role $role has no agent_id. Cannot keep a snapshot."
[ -n "$cwd" ] || block "read-only role $role has no cwd. Cannot check the repo."
# agent_id is used in a file name: keep only safe characters.
safe_id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')"
case "$safe_id" in "" | . | ..) safe_id="x$safe_id" ;; esac

gitc() { git -C "$cwd" "$@"; }

common="$(gitc rev-parse --git-common-dir 2>/dev/null)" || block "cwd is not a git repo. Cannot check the role $role."
case "$common" in /*) ;; *) common="$cwd/$common" ;; esac
dir="$common/mqtt-lens-ro"
snap="$dir/$safe_id"

# state: print HEAD, reflog length, then the status lines.
state() {
  local head status n
  head="$(gitc rev-parse HEAD 2>/dev/null)" || return 1
  status="$(gitc status --porcelain=v1 -uall 2>/dev/null)" || return 1
  n="$(gitc reflog show HEAD 2>/dev/null | wc -l | tr -d ' ')" || return 1
  printf '%s\n%s\n%s' "$head" "$n" "$status"
}

case "$event" in
  SubagentStart)
    cur="$(state)" || block "cannot read the repo state for $role."
    mkdir -p "$dir" || block "cannot create $dir."
    printf '%s' "$cur" >"$snap" || block "cannot write the snapshot for $role."
    exit 0
    ;;
  SubagentStop) ;;
  *) block "unknown hook_event_name for read-only role $role." ;;
esac

[ "$active" = "true" ] && exit 0

[ -r "$snap" ] || block "no snapshot for read-only role $role ($id). Cannot show that the repo is unchanged."

old_head="$(sed -n 1p "$snap")"
old_n="$(sed -n 2p "$snap")"
old_status="$(sed -n '3,$p' "$snap")"

cur="$(state)" || block "cannot read the repo state for $role."
new_head="$(sed -n 1p <<<"$cur")"
new_n="$(sed -n 2p <<<"$cur")"
new_status="$(sed -n '3,$p' <<<"$cur")"

problems=""

if [ "$old_status" != "$new_status" ]; then
  # Paths on lines that exist in only one of the two statuses (path starts at column 4).
  paths="$(
    diff <(printf '%s\n' "$old_status") <(printf '%s\n' "$new_status") |
      sed -n -E 's/^[<>] .{2} //p' | sort -u | tr '\n' ' '
  )"
  problems="changed paths: ${paths:-(unknown)}"
fi

if [ "$old_head" != "$new_head" ]; then
  added=$((new_n - old_n))
  if [ "$added" -le 0 ]; then
    problems="$problems; HEAD moved ($old_head to $new_head) and the reflog does not explain it"
  else
    # Only "checkout:" entries are allowed. Anything else (commit, reset, merge, rebase) blocks.
    bad="$(gitc reflog show -n "$added" --format=%gs HEAD 2>/dev/null | grep -v '^checkout:' || true)"
    if [ -n "$bad" ]; then
      problems="$problems; new commit or HEAD change ($old_head to $new_head): $(tr '\n' '|' <<<"$bad")"
    fi
  fi
fi

if [ -n "$problems" ]; then
  block "read-only role $role changed the repo: ${problems#; }. Undo the change, then stop again."
fi

rm -f "$snap"
exit 0
