#!/usr/bin/env bash
# Tests for the deny-list scan code: large input (> 64 KiB, hit on first and last line),
# and invalid regex entries (fail closed). Uses a throwaway deny-list; no real data.
# Usage: scripts/ci/test/scan_test.sh   (exit 0 = all pass)
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
# expect NAME WANT_RC GOT_RC
expect() { if [ "$3" -eq "$2" ]; then ok "$1"; else bad "$1 (want rc $2, got $3)"; fi; }

export MQTTLENS_DENYLIST="$tmp/denylist"
printf '# comment\n\nzzneedle[0-9]+\n' > "$MQTTLENS_DENYLIST"

# shellcheck source=../../../.githooks/lib.sh
. "$root/.githooks/lib.sh"
set +e +u # lib.sh sets -e; the tests check exit codes themselves

filler="$tmp/filler.txt"
yes 'plain filler line with no match at all, padding padding padding' | head -n 3000 > "$filler"
size="$(wc -c < "$filler")"
[ "$size" -gt 65536 ] || bad "filler is only $size bytes"

{ echo "zzneedle42 first"; cat "$filler"; } > "$tmp/first.txt"
{ cat "$filler"; echo "zzneedle42 last"; } > "$tmp/last.txt"
cp "$filler" "$tmp/none.txt"

# scan_stream
for f in first last; do
  scan_stream "t" < "$tmp/$f.txt" 2>/dev/null; expect "scan_stream big, hit on $f line" 1 $?
done
scan_stream "t" < "$tmp/none.txt" 2>/dev/null; expect "scan_stream big, no hit" 0 $?

# scan_diff: diff over 64 KiB, added lines
for f in first last none; do { echo "+++ b/f.txt"; sed 's/^/+/' "$tmp/$f.txt"; } > "$tmp/$f.diff"; done
scan_diff "t" < "$tmp/first.diff" 2>/dev/null; expect "scan_diff big, hit on first line" 1 $?
scan_diff "t" < "$tmp/last.diff" 2>/dev/null; expect "scan_diff big, hit on last line" 1 $?
scan_diff "t" < "$tmp/none.diff" 2>/dev/null; expect "scan_diff big, no hit" 0 $?

# denylist-scan.sh on big files
for f in first last; do
  "$root/scripts/denylist-scan.sh" "$tmp/$f.txt" >/dev/null 2>&1; expect "denylist-scan big, hit on $f line" 1 $?
done
"$root/scripts/denylist-scan.sh" "$tmp/none.txt" >/dev/null 2>&1; expect "denylist-scan big, no hit" 0 $?

# denylist-range.sh in a scratch repo. mkrepo NAME: new repo with one base commit.
mkrepo() {
  local r="$tmp/$1"
  mkdir "$r"
  git -C "$r" init -q
  git -C "$r" config user.name t
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config commit.gpgsign false
  git -C "$r" config core.hooksPath /dev/null
  echo base > "$r/a"
  git -C "$r" add a
  git -C "$r" commit -qm base
}
# range NAME: run denylist-range.sh over base..HEAD in the scratch repo, return its status
range() {
  (cd "$tmp/$1" && "$root/scripts/ci/denylist-range.sh" HEAD~1 HEAD >"$tmp/$1.out" 2>&1)
}
for f in first last none; do
  mkrepo "diff-$f"
  cp "$tmp/$f.txt" "$tmp/diff-$f/big.txt"
  git -C "$tmp/diff-$f" add big.txt
  git -C "$tmp/diff-$f" commit -qm "add big"
  mkrepo "msg-$f"
  git -C "$tmp/msg-$f" commit -q --allow-empty -F "$tmp/$f.txt"
done
range diff-first; expect "denylist-range big diff, hit on first line" 1 $?
range diff-last; expect "denylist-range big diff, hit on last line" 1 $?
range diff-none; expect "denylist-range big diff, no hit" 0 $?
range msg-first; expect "denylist-range big message, hit on first line" 1 $?
range msg-last; expect "denylist-range big message, hit on last line" 1 $?
range msg-none; expect "denylist-range big message, no hit" 0 $?

# Invalid regex (deny-list line 4 here): every scan fails with a clear message.
export MQTTLENS_DENYLIST="$tmp/badlist"
# shellcheck disable=SC2034
DENYLIST="$MQTTLENS_DENYLIST" # lib.sh read the variable at source time
printf '# comment\nzzneedle[0-9]+\n\nzz(unclosed\n' > "$MQTTLENS_DENYLIST"
want="deny-list line 4 is not a valid regex"
msg="zz(unclosed here"
out="$(printf '%s\n' "$msg" | scan_stream t 2>&1)"; rc=$?
expect "scan_stream invalid regex fails" 1 $rc
case "$out" in *"$want"*) ok "scan_stream invalid regex message" ;; *) bad "scan_stream invalid regex message: $out" ;; esac
out="$(printf '+++ b/f\n+%s\n' "$msg" | scan_diff t 2>&1)"; rc=$?
expect "scan_diff invalid regex fails" 1 $rc
case "$out" in *"$want"*) ok "scan_diff invalid regex message" ;; *) bad "scan_diff invalid regex message: $out" ;; esac
printf 'clean text\n' > "$tmp/clean.txt"
out="$("$root/scripts/denylist-scan.sh" "$tmp/clean.txt" 2>&1)"; rc=$?
expect "denylist-scan invalid regex fails" 1 $rc
case "$out" in *"$want"*) ok "denylist-scan invalid regex message" ;; *) bad "denylist-scan invalid regex message: $out" ;; esac
range diff-none; expect "denylist-range invalid regex fails" 1 $?
grep -q "$want" "$tmp/diff-none.out"; expect "denylist-range invalid regex message" 0 $?

if [ "$fails" -eq 0 ]; then echo "scan_test: all passed"; else echo "scan_test: $fails failed"; fi
[ "$fails" -eq 0 ]
