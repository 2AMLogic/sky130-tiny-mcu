# Work Log

Chronological record of merged PRs and closed issues, maintained by the Guide role.
Older months rotate into `work_log/` (see the `## Archives` index).

## Archives

_None yet._

## Log

### 2026-11-25

- **PR #48**: fix: derive run_flow_smoke PDK variant from setup-env.sh pin
- **PR #46**: refactor: delegate run_flow_smoke's pin checks to setup-env.sh --check-flow
- **Issue #47** (closed): Nothing ties run_flow_smoke.py's PDK_VARIANT to setup-env.sh's PIN_PDK_VARIANT
- **Issue #45** (closed): Remove duplicate flow-pin check from verification/tools/run_flow_smoke.py: delegate preflight to scripts/setup-env.sh --check-flow

### 2026-11-24

- **PR #44**: fix: fail --check-flow on an empty klt_required_commands list
- **PR #42**: fix: read klt_required_commands once and fail when the field is missing
- **Issue #43** (closed): An empty klt_required_commands list still passes the flow preflight with an empty success line
- **Issue #40** (closed): Read the required KLT command list once in the flow preflight

### 2026-11-22

- **PR #33**: flow-smoke: pair netlist_sha256 with a banner-normalised hash; record the banner-cause finding
- **Issue #34** (closed): flow-smoke: netlist_sha256_banner_normalised is only in the run log, not in a structured record field
- **Issue #32** (closed): flow-smoke's recorded netlist_sha256 is not reproducible across two runs at the same pinned Yosys version
- **PR #29**: fix: pin the klayout engine exactly and fail --check-flow when it drifts
- **PR #27**: fix: reject legacy YYYY-MM-DD record dirs in records linter
- **Issue #26** (closed): Pin the klayout engine version exactly, not just a floor: flow-smoke ran 0.30.13 against a klt build tested on 0.30.12
- **Issue #23** (closed): Remove legacy YYYY-MM-DD record branch from verification/tools/lint_records.py: dead sibling carryover that bypasses provenance.json
- **PR #28**: fix: fail flow-smoke LVS gate on unchecked power-connectivity pins
- **PR #24**: feat: run the smoke DUT through klt synthesize/P&R/STA/DRC/LVS/ERC, recorded
- **PR #22**: chore(loom): resync installed Loom to v0.20.8 (clears the dispatch hold)
- **Issue #25** (closed): flow-smoke LVS gate passes while a declared power-connectivity expectation goes unverified (unchecked_expected_pins)
- **Issue #21** (closed): Bootstrap the implementation-flow harness: run the smoke DUT through klt synthesize, place-and-route, STA, DRC, LVS and ERC, and record it

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
