#!/usr/bin/env bash
# PreToolUse (Bash) policy hook. All sessions. Exit 2 blocks the call.
# Input (stdin JSON): tool_name, tool_input.command, cwd.
#
# Blocks (see specs/process/guardrails.md#hooks):
#   gh pr merge (and the API routes to a merge); gh release; gh alias
#   git push to main/master, force pushes, mass pushes (--all, --mirror, --tags)
#   git reset --hard while on main (or when the branch cannot be read)
#   git tag (create); docker/podman/buildah/nerdctl push
# Before any gh call or git push, the active gh account must be BillyGrande.
# Set MQTTLENS_GH_LOGIN to skip the lookup (tests only).
#
# Fail closed: unreadable input, unknown branch and failed account lookup all block.
# Limits: a shell string is split on ; & | ( ) { } and backticks, so a quoted text with
# these characters can cause a false block. Variable indirection (git $X) is not seen.
set -u

REQUIRED_LOGIN="BillyGrande"

block() {
  echo "BLOCKED by bash-policy: $*" >&2
  exit 2
}

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null)" || block "hook input is not valid JSON"
if [ -n "$tool" ] && [ "$tool" != "Bash" ]; then
  exit 0
fi
cmd="$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)" || block "hook input is not valid JSON"
cwd="$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null)" || block "hook input is not valid JSON"
[ -n "$cwd" ] || cwd="$PWD"
[ -n "$cmd" ] || exit 0

login_checked=0

check_account() {
  [ "$login_checked" -eq 1 ] && return 0
  local login="${MQTTLENS_GH_LOGIN:-}"
  if [ -z "$login" ]; then
    login="$(timeout 15 gh api user -q .login 2>/dev/null)" || login=""
  fi
  if [ "$login" != "$REQUIRED_LOGIN" ]; then
    block "the active gh account is not $REQUIRED_LOGIN. Run: gh auth switch --user $REQUIRED_LOGIN"
  fi
  login_checked=1
}

# Current branch of the repo that a git command targets. Empty = unknown.
current_branch() {
  git -C "$cwd" "$@" symbolic-ref --short -q HEAD 2>/dev/null || true
}

on_protected_branch() {
  local b
  b="$(current_branch "$@")"
  [ -z "$b" ] || [ "$b" = "main" ] || [ "$b" = "master" ]
}

is_protected_ref() {
  case "$1" in
    main | master | refs/heads/main | refs/heads/master) return 0 ;;
  esac
  return 1
}

handle_git() {
  local -a gopts=() pos=()
  local sub="" a
  while [ $# -gt 0 ]; do
    a="$1"
    shift
    case "$a" in
      -C | --git-dir | --work-tree | --namespace | -c | --exec-path)
        case "$a" in
          -C | --git-dir | --work-tree) gopts+=("$a" "${1:-}") ;;
        esac
        shift || true
        ;;
      --git-dir=* | --work-tree=*) gopts+=("$a") ;;
      -*) ;;
      *)
        sub="$a"
        pos=("$@")
        break
        ;;
    esac
  done
  # -C with a relative path is relative to cwd (git -C "$cwd" -C rel works the same).
  case "$sub" in
    push) git_push "${gopts[@]}" -- "${pos[@]}" ;;
    reset)
      for a in "${pos[@]}"; do
        case "$a" in
          --hard | --hard=*)
            if on_protected_branch "${gopts[@]}"; then
              block "git reset --hard on main (or unknown branch) is not allowed"
            fi
            ;;
        esac
      done
      ;;
    tag) git_tag "${pos[@]}" ;;
  esac
}

git_push() {
  local -a gopts=() args=() refs=()
  local a b
  while [ "$1" != "--" ]; do
    gopts+=("$1")
    shift
  done
  shift
  args=("$@")
  local i=0 npos=0 skip=0
  for a in "${args[@]}"; do
    if [ "$skip" -eq 1 ]; then
      skip=0
      continue
    fi
    case "$a" in
      --force | --force-with-lease | --force-with-lease=* | --force-if-includes | --all | --mirror | --tags | --follow-tags | --prune)
        block "git push with $a is not allowed"
        ;;
      -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
      --*) ;;
      -*)
        case "$a" in
          *f*) block "git push with $a (force) is not allowed" ;;
        esac
        ;;
      *)
        npos=$((npos + 1))
        if [ "$npos" -gt 1 ]; then refs+=("$a"); fi
        ;;
    esac
    i=$((i + 1))
  done
  for a in "${refs[@]}"; do
    case "$a" in
      +*) block "git push with a + (force) refspec is not allowed" ;;
      *\** | *\?* | *\[*) block "git push with a glob refspec is not allowed" ;;
    esac
    b="${a##*:}"
    case "$b" in
      refs/tags/* | tags/*) block "pushing tags is owner-only" ;;
    esac
    if is_protected_ref "$b" || is_protected_ref "$a"; then
      block "git push to main/master is not allowed"
    fi
    if [ "$b" = "HEAD" ] || [ "$b" = "@" ]; then
      if on_protected_branch "${gopts[@]}"; then
        block "git push of HEAD from main (or unknown branch) is not allowed"
      fi
    fi
  done
  if [ "${#refs[@]}" -eq 0 ]; then
    if on_protected_branch "${gopts[@]}"; then
      block "git push from main (or unknown branch) is not allowed"
    fi
  fi
  check_account
}

git_tag() {
  [ $# -eq 0 ] && return 0
  local a
  case "$1" in
    -l | --list | -n | -n[0-9]* | -v | --verify | --contains | --points-at | --merged | --no-merged | --sort | --sort=* | --format=* | --column | -i | --ignore-case) ;;
    *) block "git tag (create) is owner-only" ;;
  esac
  for a in "$@"; do
    case "$a" in
      --annotate | --sign | --delete | --force | --message | --local-user | --file | --create-reflog)
        block "git tag (create) is owner-only"
        ;;
      --*) ;;
      -[a-zA-Z]*)
        case "$a" in
          -*[asumfdF]*) block "git tag (create) is owner-only" ;;
        esac
        ;;
    esac
  done
}

handle_gh() {
  local -a pos=()
  local a skip=0
  for a in "$@"; do
    if [ "$skip" -eq 1 ]; then
      skip=0
      continue
    fi
    case "$a" in
      -R | --repo | --hostname) skip=1 ;;
      -*) ;;
      *) pos+=("$a") ;;
    esac
  done
  local c0="${pos[0]:-}" c1="${pos[1]:-}"
  case "$c0" in
    release) block "gh release is owner-only" ;;
    alias) block "gh alias could hide a blocked command" ;;
    pr)
      [ "$c1" = "merge" ] && block "gh pr merge is owner-only"
      ;;
    api)
      for a in "$@"; do
        case "$a" in
          */merge | */merge/* | */merge\?* | merge) block "merging through gh api is owner-only" ;;
          *mergePullRequest* | *AutoMerge* | *autoMerge*) block "merging through gh api is owner-only" ;;
          */releases | */releases/* | */git/refs | */git/refs/* | */git/tags | */git/tags/*) block "releases, refs and tags through gh api are owner-only" ;;
        esac
      done
      ;;
    auth) return 0 ;;
  esac
  check_account
}

check_segment() {
  local seg="$1" depth="$2"
  local -a raw=() toks=()
  local t name i skipnext=0 start=-1
  read -ra raw <<<"$seg"
  for t in "${raw[@]}"; do
    t="${t//[\'\"\\]/}"
    [ -n "$t" ] && toks+=("$t")
  done
  [ "${#toks[@]}" -gt 0 ] || return 0
  for ((i = 0; i < ${#toks[@]}; i++)); do
    t="${toks[$i]}"
    if [ "$skipnext" -eq 1 ]; then
      skipnext=0
      continue
    fi
    name="${t##*/}"
    case "$t" in
      [A-Za-z_]*=*) continue ;;
    esac
    case "$name" in
      sudo | doas | command | env | nohup | time | exec | builtin | nice | ionice | xargs | stdbuf)
        continue
        ;;
      timeout)
        skipnext=1
        continue
        ;;
    esac
    case "$t" in
      -u | -g | -C | -h | -p | -U) skipnext=1 && continue ;;
      -*) continue ;;
    esac
    start=$i
    break
  done
  [ "$start" -ge 0 ] || return 0
  name="${toks[$start]##*/}"
  local -a args=("${toks[@]:$((start + 1))}")
  case "$name" in
    git) handle_git "${args[@]}" ;;
    gh) handle_gh "${args[@]}" ;;
    docker | podman | buildah | nerdctl)
      for t in "${args[@]}"; do
        case "$t" in
          push | --push | --push=* | type=registry*) block "image push is owner-only" ;;
        esac
      done
      ;;
    bash | sh | zsh | dash | ksh)
      for ((i = 0; i < ${#args[@]}; i++)); do
        case "${args[$i]}" in
          -c | -[a-z]c | -c[a-z] | -[a-z]c[a-z])
            check_string "${args[*]:$((i + 1))}" $((depth + 1))
            break
            ;;
        esac
      done
      ;;
    eval) check_string "${args[*]}" $((depth + 1)) ;;
  esac
}

check_string() {
  local s="$1" depth="$2" seg
  [ "$depth" -le 5 ] || block "command nesting is too deep to check"
  s="${s//\$\(/;}"
  s="${s//\`/;}"
  while IFS= read -r seg || [ -n "$seg" ]; do
    check_segment "$seg" "$depth"
  done < <(printf '%s' "$s" | tr '\n;&|(){}' '\n')
}

check_string "$cmd" 0
exit 0
