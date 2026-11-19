#!/usr/bin/env bash
# test-check-work-plan-stamp.sh — fixture test for check-work-plan-stamp.sh (#11).
#
# Builds throwaway git repos with chosen author/committer dates and asserts
# BOTH outcomes of the guard: the PR #10 shape (stamp +3m01s after the commit)
# must fail, and consistent stamps must pass. Skips (no stamp line, HEAD not
# touching WORK_PLAN.md, missing file, no commit in the judged range, missing
# file at HEAD) must pass. Cases 12-16 pin the CI shapes that made the first
# version pass vacuously: a shallow grafted merge tip (exit 2 — cannot
# determine the commit under test), a violation inherited at a full-history
# merge tip inside the judged range (exit 1 — the combined-diff skip), a
# violation outside the judged range (skip — an already-merged stamp is not
# re-judged), and a dirty working tree (the stamp is read from HEAD's blob).
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
run_case() { # run_case <want-exit> <desc> <repo-dir> [guard-args...]
  local want="$1" desc="$2" repo="$3" got=0
  shift 3
  ( cd "$repo" && "$check" "$@" ) >"$work/last-case.log" 2>&1 || got=$?
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

# 5. HEAD does not change WORK_PLAN.md, but full-history mode (no base)
#    judges the last commit that changed it — a violating stamp is caught
#    wherever it was authored, not only at the tip.
r="$work/head-other-file"
new_repo "$r"
write_plan "$r" 2026-11-19T09:02:00Z
commit_at "$r" 2026-11-19T08:58:59Z "plan with future stamp"
printf 'other\n' >"$r/OTHER.md"
commit_at "$r" 2026-11-19T10:00:00Z "touch other file only"
run_case 1 "full-history mode catches a violating stamp on an older commit (HEAD not touching WORK_PLAN.md)" "$r"

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
run_case 0 "clean merge tip passes (stamp judged at the parent commit that wrote WORK_PLAN.md, not the merge)" "$r"

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

# 12. Judged range excludes the violating commit (the PR-base shape): an
#     older, already-merged stamp is not re-judged by a range that does not
#     contain it — the guard skips.
r="$work/range-excludes"
new_repo "$r"
write_plan "$r" 2026-11-19T09:02:00Z
commit_at "$r" 2026-11-19T08:58:59Z "plan with future stamp"
printf 'other\n' >"$r/OTHER.md"
commit_at "$r" 2026-11-19T10:00:00Z "touch other file only"
bad="$(git -C "$r" rev-parse HEAD~1)"
run_case 0 "judged range excluding the violating commit skips (no re-judging of merged history)" "$r" "$bad"

# 13. Shallow grafted merge tip (the actions/checkout default this PR's own
#     CI run produced): a depth-1 clone of a clean merge whose WORK_PLAN.md
#     carries a future stamp used to PASS vacuously — the grafted tip made
#     diff-tree list every file and the only committer date available was
#     the clone ref's. The guard must refuse loudly, never pass.
r="$work/shallow-merge-src"
new_repo "$r"
printf 'other\n' >"$r/OTHER.md"
commit_at "$r" 2026-11-19T08:00:00Z "base other"
git -C "$r" checkout -qb side
write_plan "$r" 2026-11-19T09:02:00Z
commit_at "$r" 2026-11-19T08:58:59Z "plan with future stamp"
git -C "$r" checkout -q main
printf 'other2\n' >"$r/OTHER.md"
commit_at "$r" 2026-11-19T09:05:00Z "other2 on main"
git -C "$r" checkout -q side
GIT_AUTHOR_DATE=2026-11-19T09:50:00Z GIT_COMMITTER_DATE=2026-11-19T09:50:00Z \
  git -C "$r" merge -q --no-ff main -m "merge main"
git clone -q --depth 1 --branch side "file://$r" "$work/shallow-merge"
run_case 2 "shallow grafted merge tip refuses loudly (cannot determine the commit under test)" "$work/shallow-merge"

# 14. Clean merge tip whose WORK_PLAN.md is inherited from one parent that
#     carries a future stamp, judged with a range containing that commit:
#     fails. The first version combined-diff-skipped exactly this shape
#     (issue #11, measurement B).
r="$work/merge-inherited"
new_repo "$r"
printf 'seed\n' >"$r/SEED.md"
commit_at "$r" 2026-11-19T08:00:00Z "seed"
base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" checkout -qb side
write_plan "$r" 2026-11-19T09:02:00Z
commit_at "$r" 2026-11-19T08:58:59Z "plan with future stamp"
git -C "$r" checkout -q main
printf 'seed2\n' >"$r/SEED.md"
commit_at "$r" 2026-11-19T09:05:00Z "seed2 on main"
git -C "$r" checkout -q side
GIT_AUTHOR_DATE=2026-11-19T09:50:00Z GIT_COMMITTER_DATE=2026-11-19T09:50:00Z \
  git -C "$r" merge -q --no-ff main -m "merge main"
run_case 1 "merge tip inheriting a violating WORK_PLAN.md from one parent fails inside the judged range" "$r" "$base"

# 15. Same shape as 14 with a compliant inherited stamp: passes.
r="$work/merge-inherited-ok"
new_repo "$r"
printf 'seed\n' >"$r/SEED.md"
commit_at "$r" 2026-11-19T08:00:00Z "seed"
base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" checkout -qb side
write_plan "$r" 2026-11-19T08:55:00Z
commit_at "$r" 2026-11-19T08:58:59Z "plan with compliant stamp"
git -C "$r" checkout -q main
printf 'seed2\n' >"$r/SEED.md"
commit_at "$r" 2026-11-19T09:05:00Z "seed2 on main"
git -C "$r" checkout -q side
GIT_AUTHOR_DATE=2026-11-19T09:50:00Z GIT_COMMITTER_DATE=2026-11-19T09:50:00Z \
  git -C "$r" merge -q --no-ff main -m "merge main"
run_case 0 "merge tip inheriting a compliant WORK_PLAN.md from one parent passes" "$r" "$base"

# 16. Dirty working tree: the stamp is read from HEAD's blob, so an
#     uncommitted future stamp in the tree must not fail a compliant HEAD.
r="$work/dirty-tree"
new_repo "$r"
write_plan "$r" 2026-11-19T08:55:00Z
commit_at "$r" 2026-11-19T09:00:00Z "plan with compliant stamp"
printf '# Work Plan\n\n_Generated: 2026-11-19T23:59:00Z (snapshot; compare against live labels)_\n' >"$r/WORK_PLAN.md"
run_case 0 "dirty working tree does not affect the judgment (stamp read from HEAD's blob)" "$r"

echo
echo "check-work-plan-stamp fixture test: $pass passed, $fail failed"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
