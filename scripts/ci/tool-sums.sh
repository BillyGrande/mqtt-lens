#!/usr/bin/env bash
# Check the SHA-256 of the Tailwind and esbuild binaries in _build/ against
# config/tool-sums.txt. Run it after `mix assets.setup` and BEFORE the first run of the
# binaries. It never runs them. Fails closed: any problem exits 1.
# Usage: scripts/ci/tool-sums.sh [ROOT]   (default: the repository root)
set -uo pipefail

fail() {
  echo "tool-sums: $*" >&2
  exit 1
}

root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}" || fail "cannot find the root"
[ -d "$root" ] || fail "root is not a directory"
config="$root/config/config.exs"
sums="$root/config/tool-sums.txt"
[ -f "$config" ] || fail "config/config.exs is missing"
[ -f "$sums" ] || fail "config/tool-sums.txt is missing"

os="$(uname -s)" || fail "uname failed"
arch="$(uname -m)" || fail "uname failed"
case "$os/$arch" in
  Linux/x86_64 | Linux/amd64) tw_target=linux-x64 es_target=linux-x64 ;;
  Linux/aarch64 | Linux/arm64) tw_target=linux-arm64 es_target=linux-arm64 ;;
  Darwin/arm64) tw_target=macos-arm64 es_target=darwin-arm64 ;;
  Darwin/x86_64) tw_target=macos-x64 es_target=darwin-x64 ;;
  *) fail "unsupported platform $os/$arch" ;;
esac

# Version of a tool in config/config.exs: the first `version: "x"` line after `config :<tool>,`.
config_version() {
  awk -v tool="$1" '
    $0 ~ "^config :" tool ",[[:space:]]*$" { on = 1; next }
    on && /^[[:space:]]*version:[[:space:]]*"[^"]*",?[[:space:]]*$/ {
      v = $0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); print v; exit
    }
    on && /^config / { exit }
  ' "$config"
}

# Single value of a pattern in tool-sums.txt. Fails when there is none or they disagree.
single() {
  local found
  found="$(sort -u)" || return 1
  [ -n "$found" ] || return 1
  [ "$(printf '%s\n' "$found" | wc -l)" -eq 1 ] || return 1
  printf '%s\n' "$found"
}

check_tool() {
  local tool="$1" key="$2" bin="$3" shown cfg_v sums_v want got
  shown="${bin#"$root"/}"
  cfg_v="$(config_version "$tool")" || fail "$tool: cannot read the version from config/config.exs"
  [ -n "$cfg_v" ] || fail "$tool: no version in config/config.exs"
  sums_v="$(awk -v tool="$tool" '$1 == "version" && $2 == tool && NF == 3 { print $3 }' "$sums" | single)" \
    || fail "$tool: no single version line in config/tool-sums.txt"
  [ "$cfg_v" = "$sums_v" ] \
    || fail "$tool: version in config/config.exs ($cfg_v) differs from config/tool-sums.txt ($sums_v)"
  # Comment lines never count.
  want="$(awk -v key="$key" '$0 !~ /^#/ && NF == 2 && $2 == key { print $1 }' "$sums" | single)" \
    || fail "$tool: no single sum line for $key in config/tool-sums.txt"
  printf '%s\n' "$want" | grep -Eq '^[0-9a-f]{64}$' \
    || fail "$tool: the sum for $key is not 64 lowercase hex characters"
  { [ -f "$bin" ] && [ ! -L "$bin" ]; } || fail "$tool: binary $shown is missing or not a regular file"
  got="$(sha256sum -- "$bin" | awk '{ print $1 }')" || fail "$tool: cannot hash $shown"
  [ "$got" = "$want" ] || fail "$tool: SHA-256 of $shown does not match config/tool-sums.txt"
  echo "tool-sums: $tool $cfg_v ($key) ok"
}

tw_version="$(config_version tailwind)" || fail "tailwind: cannot read the version"
[ -n "$tw_version" ] || fail "tailwind: no version in config/config.exs"

check_tool tailwind "tailwind-$tw_target" "$root/_build/tailwind-$tw_target-$tw_version"
check_tool esbuild "esbuild-$es_target" "$root/_build/esbuild-$es_target"
