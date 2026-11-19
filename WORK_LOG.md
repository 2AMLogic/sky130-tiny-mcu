# Work Log

Chronological record of merged PRs and closed issues, maintained by the Guide role.
Older months rotate into `work_log/` (see the `## Archives` index).

## Archives

_None yet._

## Log

### 2026-11-19

- **Issue #14** (closed): CI: the smoke job now verifies the PR head, not the merge result — decide that deliberately and fix the stale rationale
- **PR #19**: ci: verify the merge result in the smoke job again
- **Issue #15** (closed): WORK_PLAN stamp guard: malformed/duplicate-stamp checks ignore the judged range, and main still carries a violating stamp
- **PR #16**: fix: judge WORK_PLAN stamp range gate before well-formedness checks
- **Issue #18** (closed): main's WORK_PLAN.md stamp postdates its commit, so a range reaching past a24004f reds an unrelated PR
- **PR #13**: ci: guard WORK_PLAN stamp against postdating its commit
- **Issue #11** (closed): WORK_PLAN `_Generated:` stamp is not tied to generation time (postdates its own commit)
- **PR #8**: fix: probe tool versions before any smoke record write; README pins point at setup-env.sh
- **Issue #7** (closed): verification harness: two remaining pin/record drift surfaces (half-written record on probe failure; duplicated pin literals in README)
- **PR #5**: harness: add cocotb+Icarus smoke runner with recorded evidence and CI
- **Issue #2** (closed): Bootstrap the verification harness
