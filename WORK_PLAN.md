# Work Plan

Backlog snapshot from current GitHub label state, maintained by the Guide role.

The body below is a snapshot of GitHub label state as of the last merged docs-maintenance PR — it may lag live labels until the next one merges. The `_Generated:` stamp at the top of the generated region dates the snapshot; `git log -1 -- WORK_PLAN.md` finds the merge that wrote it.

<!-- Maintained automatically by the Guide triage agent. Manual edits are fine but may be overwritten. -->
<!-- guide:plan-body:start -->
_Generated: 2026-11-28T10:14:49Z (snapshot; compare against live labels)_
## Operator Attention: Merge-Risk-Hold Pileup

Judge-approved PRs under a hold (`loom:blocked` or `loom:operator`) — a human merge decision, or the prerequisite shown, is missing.

- **#6**: spec: draft target table and seven decision records *(held: champion ratification hold)*
- **#52**: chore: resync installed Loom surfaces *(held: champion merge-risk hold)*

## Very Important

`loom:very-important` (one counts per workspace); every stage takes these first.

_None._

## Important

`loom:important`; taken before unlabelled work.

- **#1**: Draft and ratify the target spec

## Ready

Human-approved issues (`loom:issue`) ready for implementation — excluding held (`loom:blocked`/`loom:operator`/`loom:frozen`), `loom:building`, and issues with an open linked PR (native admission `OPEN_PR`; listed under Issues with Open PRs).

_None._

## Issues with Open PRs (Not Dispatchable)

`loom:issue` issues an open linked PR already holds — native admission would refuse them (`OPEN_PR`); listed with the PR and its stage, not counted above.

- **#1**: Draft and ratify the target spec — open PR #6 (held)

## In Progress

Issues currently being built (`loom:building`).

_None._

## PRs Awaiting Review

PRs waiting on Judge (`loom:review-requested`).

_None._

## Approved (Awaiting Merge)

PRs that passed review (`loom:pr`); unmarked PRs are queued for Champion auto-merge, PRs marked `*(held …)*` are not (the hold decides).

- **#6**: spec: draft target table and seven decision records — closes #1 *(held: champion ratification hold)*
- **#52**: chore: resync installed Loom surfaces *(held: champion merge-risk hold)*

## Proposed

Issues carrying `loom:curated`.

- **#1**: Draft and ratify the target spec *(curated)*

## Proposed (Architect / Hermit)

- **#12**: Remove or make honest the package.json stub: scripts exit 0 without checking anything *(hermit)* *(held)*

## Epics

_None._

## Backlog Balance

| Bucket | Count |
|------|-------|
| Operator merge-risk holds | 2 |
| Very important | 0 |
| Important | 1 |
| Ready (`loom:issue`, net of holds/building/open-linked-PRs) | 0 |
| In Progress (`loom:building`) | 0 |
| Held, no other bucket | 2 |
| PRs awaiting review | 0 |
| Approved PRs awaiting merge | 2 |
| Curated | 1 |
| Architect / Hermit proposals | 1 |
| Active epics | 0 |
<!-- guide:plan-body:end -->
