#!/usr/bin/env bash
# test-check-work-plan-stamp.sh — fixture test for check-work-plan-stamp.sh (#11).
#
# Builds throwaway git repos with chosen author/committer dates and asserts
# BOTH outcomes of the guard: the PR #10 shape (stamp +3m01s after the commit)
# must fail, and consistent stamps must pass. Skips (no stamp line, HEAD not
# touching WORK_PLAN.md, missing file, clean merge tip, root commit) must pass.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$here/../check-work-plan-stamp.sh"
if [[ ! -x "$check" ]]; then
  echo "test-check-work-plan-stamp: missing executable $check" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
run_case() { # run_case <want-exit> <desc> <repo-dir>
  local want="$1" desc="$2" repo="$3" got=0
  ( cd "$repo" && "$check" ) >"$work/last-case.log" 2>&1 || got=$?
  if [[ "$got" -eq "$want" ]]; then
    pass=$((pass + 1))
    echo "PASS: $desc (exit $got)"
  else
    fail=$((fail + 1))
    echo "FAIL: $desc — expected exit $want, got $got" >&2
    sed 's/^/    | /' "$work/last-case.log" >&2
  fi
}

new_repo() { # new_repo <dir> — throwaway repo with fixed identity
  git init -q -b main "$1"
  git -C "$1" config user.email fixture@example.com
  git -C "$1" config user.name "Stamp Fixture"
}
commit_at() { # commit_at <repo> <instant> <msg>
  local repo="$1" at="$2" msg="$3"
  GIT_AUTHOR_DATE="$at" GIT_COMMITTER_DATE="$at" git -C "$repo" add -A
  GIT_AUTHOR_DATE="$at" GIT_COMMITTER_DATE="$at" git -C "$repo" commit -qm "$msg"
}
write_plan() { # write_plan <repo> <stamp-instant|none>
  if [[ "$2" == none ]]; then
    printf '# Work Plan\n\n(no generated region)\n' >"$1/WORK_PLAN.md"
  else
    printf '# Work Plan\n\n_Generated: %s (snapshot; compare against live labels)_\n' "$2" >"$1/WORK_PLAN.md"
  fi
}

# 1. The PR #10 shape: stamp 09:02:00Z on a commit dated 08:58:59Z (+3m01s) fails.
r="$work/stamp-after"
new_repo "$r"
write_plan "$r" 2026-11-19T09:02:00Z
commit_at "$r" 2026-11-19T08:58:59Z "plan"
run_case 1 "stamp after commit date fails (+3m01s, PR #10 shape)" "$r"

# 2. Stamp before the commit date passes.
r="$work/stamp-before"
new_repo "$r"
write_plan "$r" 2026-11-19T08:55:00Z
commit_at "$r" 2026-11-19T09:05:00Z "plan"
run_case 0 "stamp before commit date passes" "$r"

# 3. Stamp equal to the commit date passes.
r="$work/stamp-equal"
new_repo "$r"
write_plan "$r" 2026-11-19T09:05:00Z
commit_at "$r" 2026-11-19T09:05:00Z "plan"
run_case 0 "stamp equal to commit date passes" "$r"

# 4. No stamp line: skip.
r="$work/no-stamp"
new_repo "$r"
write_plan "$r" none
commit_at "$r" 2026-11-19T09:00:00Z "plan without stamp"
run_case 0 "no _Generated: stamp line skips" "$r"

# 5. HEAD does not change WORK_PLAN.md: skip even with a future-dated stamp
#    (an older commit carrying a bad stamp is not re-judged here).
r="$work/head-other-file"
new_repo "$r"
write_plan "$r" 2026-11-19T09:02:00Z
commit_at "$r" 2026-11-19T08:58:59Z "plan with future stamp"
printf 'other\n' >"$r/OTHER.md"
commit_at "$r" 2026-11-19T10:00:00Z "touch other file only"
run_case 0 "HEAD not touching WORK_PLAN.md skips" "$r"

# 6. Missing WORK_PLAN.md: skip.
r="$work/missing-file"
new_repo "$r"
printf 'other\n' >"$r/OTHER.md"
commit_at "$r" 2026-11-19T09:00:00Z "no work plan yet"
run_case 0 "missing WORK_PLAN.md skips" "$r"

# 7. Malformed stamp (impossible instant): fails.
r="$work/malformed-impossible"
new_repo "$r"
printf '# Work Plan\n\n_Generated: 2026-13-45T99:99:99Z (snapshot; compare against live labels)_\n' >"$r/WORK_PLAN.md"
commit_at "$r" 2026-11-19T09:00:00Z "impossible stamp"
run_case 1 "malformed stamp (impossible instant) fails" "$r"

# 8. Malformed stamp (garbage instant): fails.
r="$work/malformed-garbage"
new_repo "$r"
printf '# Work Plan\n\n_Generated: not-a-timestamp (snapshot; compare against live labels)_\n' >"$r/WORK_PLAN.md"
commit_at "$r" 2026-11-19T09:00:00Z "garbage stamp"
run_case 1 "malformed stamp (garbage) fails" "$r"

# 9. Clean merge tip whose WORK_PLAN.md matches a parent: skip.
r="$work/merge-clean"
new_repo "$r"
write_plan "$r" 2026-11-19T09:30:00Z
commit_at "$r" 2026-11-19T09:30:00Z "plan"
git -C "$r" checkout -qb feature
git -C "$r" checkout -q main
printf 'other2\n' >"$r/OTHER.md"
commit_at "$r" 2026-11-19T09:40:00Z "other2 on main"
git -C "$r" checkout -q feature
GIT_AUTHOR_DATE=2026-11-19T09:50:00Z GIT_COMMITTER_DATE=2026-11-19T09:50:00Z \
  git -C "$r" merge -q --no-ff main -m "merge main"
run_case 0 "clean merge tip skips (WORK_PLAN.md from parent)" "$r"

# 10. Root commit carrying a consistent stamp: passes.
r="$work/root-commit"
new_repo "$r"
write_plan "$r" 2026-11-19T08:00:00Z
commit_at "$r" 2026-11-19T08:00:00Z "root commit with plan"
run_case 0 "root commit with consistent stamp passes" "$r"

# 11. Merge tip that resolves WORK_PLAN.md (differs from BOTH parents) with a
#     future stamp: fails — the combined-diff path must not blind-spot merges.
r="$work/merge-conflict"
new_repo "$r"
printf '# Work Plan\n\n_Generated: 2026-11-19T08:00:00Z (snapshot; compare against live labels)_\nbody v0\n' >"$r/WORK_PLAN.md"
commit_at "$r" 2026-11-19T08:00:00Z "base plan"
git -C "$r" checkout -qb side
printf '# Work Plan\n\n_Generated: 2026-11-19T08:00:00Z (snapshot; compare against live labels)_\nbody side\n' >"$r/WORK_PLAN.md"
commit_at "$r" 2026-11-19T09:00:00Z "side edit"
git -C "$r" checkout -q main
printf '# Work Plan\n\n_Generated: 2026-11-19T08:00:00Z (snapshot; compare against live labels)_\nbody main\n' >"$r/WORK_PLAN.md"
commit_at "$r" 2026-11-19T10:00:00Z "main edit"
git -C "$r" checkout -q side
if git -C "$r" merge main -m merge >/dev/null 2>&1; then
  echo "FAIL: expected merge conflict fixture to conflict" >&2
  fail=$((fail + 1))
else
  printf '# Work Plan\n\n_Generated: 2026-11-19T23:00:00Z (snapshot; compare against live labels)_\nbody resolved\n' >"$r/WORK_PLAN.md"
  git -C "$r" add WORK_PLAN.md
  GIT_AUTHOR_DATE=2026-11-19T11:00:00Z GIT_COMMITTER_DATE=2026-11-19T11:00:00Z \
    git -C "$r" commit -qm "resolve with future stamp"
  run_case 1 "merge tip resolving WORK_PLAN.md with future stamp fails" "$r"
fi

echo
echo "check-work-plan-stamp fixture test: $pass passed, $fail failed"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
