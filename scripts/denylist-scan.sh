#!/usr/bin/env bash
# Scan files for employer identifiers. Usage: scripts/denylist-scan.sh [paths...]
# Default: all tracked + untracked-not-ignored files.
# Deny-list: $MQTTLENS_DENYLIST or ~/.config/mqtt-lens/denylist (CI: from a secret).
set -euo pipefail
DENYLIST="${MQTTLENS_DENYLIST:-$HOME/.config/mqtt-lens/denylist}"
if [ ! -r "$DENYLIST" ]; then
  echo "denylist-scan: deny-list not found: $DENYLIST" >&2
  exit 1
fi
cd "$(git rev-parse --show-toplevel)"
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  mapfile -d '' files < <(git ls-files -z --cached --others --exclude-standard)
fi
rc=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  n=0
  while IFS= read -r pat; do
    n=$((n + 1))
    [[ "$pat" =~ ^[[:space:]]*(#|$) ]] && continue
    if grep -IiqE -e "$pat" -- "$f" 2>/dev/null; then
      # Print the deny-list line number, never the entry text or the matched text.
      echo "denylist-scan: hit file=$f deny-list line $n" >&2
      rc=1
    fi
  done < "$DENYLIST"
done
exit "$rc"
