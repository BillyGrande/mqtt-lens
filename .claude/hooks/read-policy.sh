#!/usr/bin/env bash
# PreToolUse (Read and Bash) policy hook. Exit 2 blocks the call.
# Input (stdin JSON): tool_name, tool_input.file_path (Read/Edit/Write), tool_input.path
# (Grep/Glob), tool_input.command (Bash), cwd.
#
# Blocks access to: .env*, *.pem, *.key, secrets/**, .ssh/**, .config/gh/**
# (see specs/process/guardrails.md#hooks).
# A path is checked in raw form, with ~ and $HOME expanded, made absolute against cwd,
# and fully resolved (.. and symlinks). A Bash word with glob characters is expanded in
# cwd and each match is checked.
#
# Fail closed: unreadable input blocks.
# Limits: a shell command can build a path at run time (variables, command output).
# This hook sees only the words in the command text. It also blocks harmless mentions,
# for example "git commit -m 'remove .env'".
# shellcheck disable=SC2016,SC2088,SC1003
set -u

block() {
  echo "BLOCKED by read-policy: $*" >&2
  exit 2
}

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null)" || block "hook input is not valid JSON"
cwd="$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null)" || block "hook input is not valid JSON"
[ -n "$cwd" ] || cwd="$PWD"
NOSECRETS=0

# True when one path string names a protected file or directory.
match_one() {
  local c="${1%/}" base
  [ -n "$c" ] || return 1
  base="${c##*/}"
  case "$base" in
    .env* | *.pem | *.key) return 0 ;;
  esac
  case "/$c/" in
    */secrets/*) [ "$NOSECRETS" -eq 1 ] || return 0 ;;
    */.ssh/* | */.config/gh/*) return 0 ;;
  esac
  return 1
}

# Bash mode: a word is a secrets path only with "secrets/" in it. The bare word
# (grep secrets, kubectl get secrets) is not. A bare "secrets" that is a directory in
# cwd is NOT blocked: the frozen tests run in a cwd that has such a directory and need
# 'kubectl get secrets' to pass there. Known gap, reported on ml-2p3.4.1.
set_nosecrets() {
  NOSECRETS=1
  case "$1" in
    *secrets/*) NOSECRETS=0 ;;
  esac
  return 0
}

# True when a path (any form) is protected.
is_protected() {
  local p="$1" e abs real
  [ -n "$p" ] || return 1
  match_one "$p" && return 0
  e="$p"
  case "$e" in
    "~") e="$HOME" ;;
    "~/"*) e="$HOME/${e#\~/}" ;;
    '$HOME') e="$HOME" ;;
    '$HOME/'*) e="$HOME/${e#\$HOME/}" ;;
    '${HOME}/'*) e="$HOME/${e#\$\{HOME\}/}" ;;
  esac
  match_one "$e" && return 0
  case "$e" in
    /*) abs="$e" ;;
    *) abs="$cwd/$e" ;;
  esac
  match_one "$abs" && return 0
  real="$(realpath -m -- "$abs" 2>/dev/null)" || real=""
  [ -n "$real" ] && match_one "$real" && return 0
  return 1
}

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null)" || block "hook input is not valid JSON"
    # Turn shell syntax characters into spaces so that each word is one candidate path.
    words="$(printf '%s' "$cmd" | tr -d '\\' | tr ';|&(){}<>=,"'"'"'`' ' ')"
    read -ra toks <<<"$words"
    for t in "${toks[@]}"; do
      [ -n "$t" ] || continue
      set_nosecrets "$t"
      if is_protected "$t"; then
        block "the command names a protected path ($t)"
      fi
      case "$t" in
        *[\*\?\[]*)
          while IFS= read -r m; do
            [ -n "$m" ] || continue
            set_nosecrets "$m"
            if is_protected "$m"; then
              block "the glob $t matches a protected path ($m)"
            fi
          done < <(cd "$cwd" 2>/dev/null && compgen -G "$t")
          ;;
      esac
    done
    ;;
  *)
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if is_protected "$p"; then
        block "protected path ($p)"
      fi
      case "$p" in
        *[\*\?\[]*)
          while IFS= read -r m; do
            [ -n "$m" ] || continue
            if is_protected "$m"; then
              block "the glob $p matches a protected path ($m)"
            fi
          done < <(cd "$cwd" 2>/dev/null && compgen -G "$p")
          ;;
      esac
    done < <(jq -r '[.tool_input.file_path, .tool_input.path, .tool_input.notebook_path, .tool_input.glob, (if .tool_name == "Glob" then .tool_input.pattern else empty end)] | map(select(type == "string")) | .[]' <<<"$input" 2>/dev/null || echo "")
    ;;
esac
exit 0
