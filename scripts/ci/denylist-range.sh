#!/usr/bin/env bash
# Scan the commit messages and the added diff lines of BASE..HEAD for employer identifiers.
# Usage: scripts/ci/denylist-range.sh BASE HEAD
# Deny-list: $MQTTLENS_DENYLIST or ~/.config/mqtt-lens/denylist (CI: from a secret).
# The beads export scan stays in the local pre-push hook: CI has no beads data.
set -euo pipefail
base="${1:?usage: denylist-range.sh BASE HEAD}"
head="${2:?usage: denylist-range.sh BASE HEAD}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../.githooks/lib.sh source-path=SCRIPTDIR
. "$here/../../.githooks/lib.sh"
require_denylist
cd "$(git rev-parse --show-toplevel)"

fail=0
# Commit messages and per-commit diffs: also catches content added in one commit
# and removed in a later one (a rebase merge keeps both in the public history).
for c in $(git rev-list "$base..$head"); do
  git log -1 --format=%B "$c" | scan_stream "message of $c" || fail=1
  git show --no-color -U0 --format= "$c" | scan_diff "diff of $c" || fail=1
done
# The PR diff as a whole.
git diff --no-color -U0 "$base...$head" | scan_diff "PR diff $base...$head" || fail=1
[ "$fail" -eq 0 ] || exit 1
echo "denylist-range: ok"
