# Work Plan

Backlog snapshot from current GitHub label state, maintained by the Guide role.

The body below is a snapshot of GitHub label state as of the last merged docs-maintenance PR — it may lag live labels until the next one merges. The `_Generated:` stamp at the top of the generated region dates the snapshot; `git log -1 -- WORK_PLAN.md` finds the merge that wrote it.

<!-- Maintained automatically by the Guide triage agent. Manual edits are fine but may be overwritten. -->
<!-- guide:plan-body:start -->
_Generated: 2026-11-22T22:16:07Z (snapshot; compare against live labels)_
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — only a human merge decision is missing.

- **#6**: spec: draft target table and seven decision records

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

_None._

## Ready

Human-approved issues (`loom:issue`) ready for implementation — excluding held (`loom:blocked`/`loom:operator`/`loom:frozen`), `loom:building`, and issues closed by an open `loom:pr` PR (listed under Approved).

_None._

## In Progress

Issues currently being built (`loom:building`).

- **#1**: Draft and ratify the target spec
- **#32**: flow-smoke's recorded netlist_sha256 is not reproducible across two runs at the same pinned Yosys version

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review and are queued for Champion auto-merge (`loom:pr`).

- **#6**: spec: draft target table and seven decision records — closes #1
- **#33**: flow-smoke: pair netlist_sha256 with a banner-normalised hash; record the banner-cause finding — closes #32

## Proposed

Issues carrying `loom:curated`.

- **#1**: Draft and ratify the target spec *(curated)*
- **#32**: flow-smoke's recorded netlist_sha256 is not reproducible across two runs at the same pinned Yosys version *(curated)*

## Proposed (Architect / Hermit)

- **#12**: Remove or make honest the package.json stub: scripts exit 0 without checking anything *(hermit)* *(held)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 1 |
| Very important | 0 |
| Important | 0 |
| Ready (`loom:issue`, net of holds/building/merge-pending) | 0 |
| In Progress (`loom:building`) | 2 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 2 |
| Curated | 2 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
