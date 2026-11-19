#!/usr/bin/env bash
# check-work-plan-stamp.sh — guard the WORK_PLAN.md `_Generated:` stamp (issue #11).
#
# On PR #10 the stamp read 09:02:00Z while the only commit carrying it was
# committed at 08:58:59Z (+3m01s), so the stamp was typed, not emitted. The
# file header tells every consumer to read the stamp as the snapshot's age,
# so this check fails any commit that changes WORK_PLAN.md while carrying a
# stamp later than its own committer date.
#
# What this bounds, and what it does not prove: freshness is BOUNDED, not
# PROVEN. A stamp earlier than the commit is accepted (a stale snapshot still
# passes); only overstating freshness is caught. Row accuracy against live
# labels needs forge access and stays out of scope.
#
# Rules:
# - Skip when WORK_PLAN.md is absent or has no `_Generated:` line (pre-#13909
#   format or empty generated region).
# - Check only when the checked-out tip (HEAD) itself changes WORK_PLAN.md;
#   the stamp of an older, already-merged commit is not re-judged here.
# - Compare against HEAD's committer date, so a later merge-from-main tip
#   whose WORK_PLAN.md is unchanged passes.
# - Compare as UTC instants (epoch seconds); a stamp equal to the commit
#   date passes.
# - A `_Generated:` line that is not a well-formed UTC instant stamp fails,
#   as do multiple stamp lines.
#
# Exit codes: 0 pass or skip; 1 stamp ahead of the commit or malformed stamp;
# 2 environmental error (not a git checkout, git/date failure).
set -euo pipefail
export LC_ALL=C

RE='^_Generated: ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z) \(snapshot; compare against live labels\)_$'

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check-work-plan-stamp: not inside a git checkout" >&2
  exit 2
}
file="$root/WORK_PLAN.md"
if [[ ! -f "$file" ]]; then
  echo "check-work-plan-stamp: skip (no WORK_PLAN.md)"
  exit 0
fi

count="$(grep -c '^_Generated:' "$file" || true)"
if [[ "$count" -eq 0 ]]; then
  echo "check-work-plan-stamp: skip (no _Generated: stamp line)"
  exit 0
fi
if [[ "$count" -gt 1 ]]; then
  echo "check-work-plan-stamp: FAIL ($count _Generated: stamp lines in WORK_PLAN.md; expected at most one)" >&2
  exit 1
fi
stamp_line="$(grep '^_Generated:' "$file")"
if [[ ! "$stamp_line" =~ $RE ]]; then
  echo "check-work-plan-stamp: FAIL (malformed _Generated: stamp line: $stamp_line)" >&2
  exit 1
fi
instant="${BASH_REMATCH[1]}"
stamp_epoch="$(date -u -d "$instant" +%s 2>/dev/null)" || {
  echo "check-work-plan-stamp: FAIL (_Generated: stamp is not a real instant: $instant)" >&2
  exit 1
}

if ! head_files="$(git diff-tree -r --cc --root --name-only --no-commit-id HEAD 2>/dev/null)"; then
  echo "check-work-plan-stamp: git diff-tree on HEAD failed" >&2
  exit 2
fi
if ! grep -qx -- 'WORK_PLAN.md' <<<"$head_files"; then
  echo "check-work-plan-stamp: skip (HEAD does not change WORK_PLAN.md)"
  exit 0
fi

commit_epoch="$(git log -1 --format=%ct HEAD)"
if (( stamp_epoch > commit_epoch )); then
  echo "check-work-plan-stamp: FAIL (_Generated: $instant postdates the commit carrying it ($(date -u -d "@$commit_epoch" +%Y-%m-%dT%H:%M:%SZ)); a stamp cannot be emitted after the commit that contains it — see issue #11)" >&2
  exit 1
fi
echo "check-work-plan-stamp: pass (stamp $instant does not postdate HEAD committer date)"
exit 0
