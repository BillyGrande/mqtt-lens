#!/usr/bin/env bash
# PreToolUse guard: enforces role limits by agent_type.
# Input: hook JSON on stdin. Exit 0 = allow, exit 2 = block (stderr goes to Claude).
# Specs: specs/process/roles.md, specs/process/orchestrator.md, specs/process/guardrails.md
set -u

block() {
  echo "guard.sh: blocked: $*" >&2
  exit 2
}

input="$(cat)"

# Fail closed: input must be one JSON object.
printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1 || block "hook input is not a JSON object"

# agent_type must be absent or a string.
printf '%s' "$input" | jq -e '(has("agent_type") | not) or (.agent_type | type == "string")' >/dev/null 2>&1 ||
  block "agent_type is not a string"

role="$(printf '%s' "$input" | jq -r '.agent_type // ""')"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""')"

# Main session (no agent_type) and unknown roles are allowed.
case "$role" in
  architect | spec-keeper | test-author | implementer | verifier | reviewer | security-reviewer | scout | orchestrator) ;;
  *) exit 0 ;;
esac

# Role allowed-path table. No entry means no writes.
allowed_dirs=""
case "$role" in
  architect | spec-keeper) allowed_dirs="specs" ;;
  test-author | implementer) allowed_dirs="lib test assets config priv" ;;
esac

# --- Orchestrator Bash allow-list
if [ "$role" = "orchestrator" ] && [ "$tool" = "Bash" ]; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
  [ -n "$cmd" ] || block "orchestrator Bash without a command"
  case "$cmd" in
    *';'* | *'&'* | *'|'* | *'`'* | *'$'* | *'>'* | *'<'* | *$'\n'* | *$'\r'*)
      block "orchestrator Bash: shell chaining or substitution is not allowed"
      ;;
  esac
  # Trim leading whitespace.
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  # git writes files with --output (git accepts any unique prefix, so block --ou*).
  case "$cmd" in
    git\ *)
      case " $cmd" in
        *[[:space:]]--ou*) block "orchestrator Bash: git --output writes files" ;;
      esac
      ;;
  esac
  case "$cmd" in
    "bd" | "bd "* | \
      "git status" | "git status "* | \
      "git log" | "git log "* | \
      "git worktree list" | "git worktree list "* | \
      "git worktree remove "* | \
      "gh pr view" | "gh pr view "* | \
      "gh pr list" | "gh pr list "* | \
      "gh pr checks" | "gh pr checks "*)
      exit 0
      ;;
  esac
  # gh pr merge <number> --rebase [--delete-branch]. Digits only. bash-policy.sh checks the rest.
  if [[ "$cmd" =~ ^gh\ pr\ merge\ [0-9]+\ --rebase(\ --delete-branch)?$ ]]; then
    exit 0
  fi
  block "orchestrator Bash: command not in allow-list"
fi

# --- Write tools: path rules
case "$tool" in
  Edit | Write | MultiEdit | NotebookEdit) ;;
  *) exit 0 ;;
esac

[ -n "$allowed_dirs" ] || block "role $role may not write files"

path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')"
[ -n "$path" ] || block "write tool without a path"
case "$path" in
  *$'\n'* | *$'\r'*) block "control character in path" ;;
esac

# Reject .. components outright.
case "/$path/" in
  */../*) block "path traversal (..) in $path" ;;
esac

cwd="$(printf '%s' "$input" | jq -r '.cwd // ""')"
[ -n "$cwd" ] || cwd="$PWD"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || block "cannot find the repo root from cwd"
root="$(realpath -e -- "$root" 2>/dev/null)" || block "cannot resolve the repo root"

case "$path" in
  /*) abs="$path" ;;
  *) abs="$root/$path" ;;
esac
# Resolve symlinks and dot segments (the file may not exist yet).
abs="$(realpath -m -- "$abs" 2>/dev/null)" || block "cannot resolve path $path"

case "$abs" in
  "$root"/*) rel="${abs#"$root"/}" ;;
  *) block "path $path is outside the repo root" ;;
esac

ok=0
for d in $allowed_dirs; do
  case "$rel" in
    "$d"/?*) ok=1 ;;
  esac
done
[ "$ok" -eq 1 ] || block "role $role may not write $rel"

# --- Test-tamper (implementer only)
if [ "$role" = "implementer" ]; then
  base=""
  for ref in main origin/main; do
    if git -C "$root" rev-parse --verify -q "$ref" >/dev/null 2>&1; then
      base="$(git -C "$root" merge-base "$ref" HEAD 2>/dev/null)" && break
      base=""
    fi
  done
  if [ -n "$base" ]; then
    range="$base..HEAD"
  else
    range="HEAD"
  fi
  shas="$(git -C "$root" log --format=%H -E --grep='^Tests-Committed: [^[:space:]]+[[:space:]]*$' "$range" 2>/dev/null)" ||
    block "cannot read the task branch history"
  for sha in $shas; do
    added="$(git -C "$root" show --name-only --diff-filter=A --format= "$sha" 2>/dev/null)" ||
      block "cannot read commit $sha"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$f" = "$rel" ]; then
        block "$rel was added by tests commit $sha and is read-only for the implementer"
      fi
    done <<<"$added"
  done
fi

exit 0
