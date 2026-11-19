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
# Usage: check-work-plan-stamp.sh [BASE_SHA]
#
# The commit judged is the latest commit in BASE_SHA..HEAD (the whole history
# of HEAD when BASE_SHA is empty) that changed WORK_PLAN.md. Judging by file
# history instead of "did HEAD change the file" is deliberate: CI checks out
# merge tips (merge_group, pushed merges) where a combined diff omits a file
# inherited unchanged from one parent, and a shallow grafted tip makes that
# diff lie in the other direction — issue #11 measured both shapes pass
# vacuously. `git log -- WORK_PLAN.md` traverses merge topology correctly, so
# a violation is caught wherever in the range it was authored.
#
# Rules:
# - Skip when WORK_PLAN.md is absent at HEAD or has no `_Generated:` line
#   (pre-#13909 format or empty generated region).
# - Skip when no commit in the range changes WORK_PLAN.md: an older,
#   already-merged stamp is not re-judged by a range that does not contain it.
# - Compare the stamp against that commit's committer date, so a merge tip
#   whose WORK_PLAN.md is inherited unchanged is judged against the commit
#   that authored the stamp, not GitHub's clock.
# - The stamp is read from HEAD's blob (`git show HEAD:WORK_PLAN.md`), so the
#   judged stamp and the judged commit refer to the same object even when the
#   working tree is dirty.
# - Compare as UTC instants (epoch seconds); a stamp equal to the commit
#   date passes.
# - A `_Generated:` line that is not a well-formed UTC instant stamp fails,
#   as do multiple stamp lines.
#
# Exit codes: 0 pass or skip; 1 stamp ahead of the commit or malformed stamp;
# 2 environmental error (not a git checkout, shallow clone — the commit under
# test cannot be determined, unresolvable BASE_SHA, git/date failure). CI
# treats 2 as failure: a check that cannot run must never look like one that
# passed.
# Portability: `date -u -d` is GNU coreutils. On BSD/macOS it fails the same
# way as any other date failure and the stamp is reported as malformed
# (exit 1) — never a silent pass. Local runs there are not expected.
set -euo pipefail
export LC_ALL=C

RE='^_Generated: ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z) \(snapshot; compare against live labels\)_$'

base="${1:-}"

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "check-work-plan-stamp: not inside a git checkout" >&2
  exit 2
}

if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" != "false" ]]; then
  echo "check-work-plan-stamp: cannot determine the commit under test (shallow clone: HEAD may be a grafted tip whose file history is missing) — fetch full history (fetch-depth: 0) and re-run" >&2
  exit 2
fi

range_spec="HEAD"
range_desc="HEAD history"
if [[ -n "${base//[[:space:]]/}" ]]; then
  if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    echo "check-work-plan-stamp: cannot determine the commit under test (BASE_SHA '$base' does not resolve to a commit)" >&2
    exit 2
  fi
  range_spec="$base..HEAD"
  range_desc="$base..HEAD"
fi

if ! head_plan="$(git show HEAD:WORK_PLAN.md 2>/dev/null)"; then
  echo "check-work-plan-stamp: skip (no WORK_PLAN.md at HEAD)"
  exit 0
fi

count="$(grep -c '^_Generated:' <<<"$head_plan" || true)"
if [[ "$count" -eq 0 ]]; then
  echo "check-work-plan-stamp: skip (no _Generated: stamp line)"
  exit 0
fi
if [[ "$count" -gt 1 ]]; then
  echo "check-work-plan-stamp: FAIL ($count _Generated: stamp lines in WORK_PLAN.md; expected at most one)" >&2
  exit 1
fi
stamp_line="$(grep '^_Generated:' <<<"$head_plan")"
if [[ ! "$stamp_line" =~ $RE ]]; then
  echo "check-work-plan-stamp: FAIL (malformed _Generated: stamp line: $stamp_line)" >&2
  exit 1
fi
instant="${BASH_REMATCH[1]}"
stamp_epoch="$(date -u -d "$instant" +%s 2>/dev/null)" || {
  echo "check-work-plan-stamp: FAIL (_Generated: stamp is not a real instant: $instant)" >&2
  exit 1
}

if ! commit_epoch="$(git log -1 --format=%ct "$range_spec" -- WORK_PLAN.md 2>/dev/null)"; then
  echo "check-work-plan-stamp: git log over $range_desc failed" >&2
  exit 2
fi
if [[ -z "$commit_epoch" ]]; then
  echo "check-work-plan-stamp: skip (no commit in $range_desc changes WORK_PLAN.md)"
  exit 0
fi

if (( stamp_epoch > commit_epoch )); then
  echo "check-work-plan-stamp: FAIL (_Generated: $instant postdates the commit carrying it ($(date -u -d "@$commit_epoch" +%Y-%m-%dT%H:%M:%SZ)); a stamp cannot be emitted after the commit that contains it — see issue #11)" >&2
  exit 1
fi
echo "check-work-plan-stamp: pass (stamp $instant does not postdate the last commit that changed WORK_PLAN.md)"
exit 0
