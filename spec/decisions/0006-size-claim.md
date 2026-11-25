# 0006 — The size claim: what is measured, against what, reproducibly

- **Status**: proposed — flips to `RATIFIED` in this PR after the two
  independent reviews (engineering and market) required by the repo
  instructions.
- **Supersedes**: the README draft row "AREA: ≤ 0.10 mm² core, RAM included
  / Stretch: ≤ 0.05 mm²" in its method-free form.
- **Superseded by**: none.
- **Spec rows**: `spec/target-spec.md` row 12 (AREA).

## Context

The repo instructions are explicit: never write "smallest" in this repo
without a measured area and the comparison it rests on, and never claim a
figure that a committed measurement does not back. The draft carries an
AREA row with no method, so nothing could later test the design against it.
This record fixes the three things a size claim needs: the measured object,
the comparison set, and the command path that reproduces the number.

Reference points, all read **2026-11-19**:

| Fact | Value | Source |
|---|---|---|
| SERV published size | 2.1kGE / 164 FF, "minimal configuration", "excluding register file", on "a typical CMOS process"; 198 LUT / 164 FF on iCE40 | olofk/serv `doc/overview.rst` at the pinned commit (record 0001) |
| GE on this PDK | `sky130_fd_sc_hd__nand2_1` = 3.7536 µm², so SERV's 2.1kGE re-reads to ≈ 0.0079 mm² of raw cells — an **indicative re-read, not our measurement** | PDK liberty, record 0002 sources |
| Signoff corners shipped by the PDK | at least `tt_025C_1v80`, `ss_100C_1v60`, `ff_n40C_1v95` liberty files | `libs.ref/sky130_fd_sc_hd/lib/` listing, PDK commit `c6d73a35…` (record 0002) |
| Sibling SoC budget for contrast | 3.8 mm² core budget, 16 KB SRAM | sky130-riscv-soc `spec/soc.md`, read 2026-11-19 |

Using the raw cell areas of record 0002, the indicative core estimate is
≈ 0.008 mm². The 256 B array costs ≈ 0.0410 mm² in flops or ≈ 0.03075 mm²
in latches, including the 144 B RF
in either case. Decode, arbitration, reset logic, boot FSM, peripherals,
clock ring, placement and routing still have to fit. The 0.05 mm² stretch
leaves only ≈ 0.011 mm² after the core estimate and latch bits. Its
feasibility requires a routed measurement.

## Decision

1. **What is measured: the post-route core area** of the full MCU — all
   standard cells plus the RAM array and clock ring inside the core
   boundary, pad-less (this block has no pad ring in scope), taken from the
   **DRC-clean, LVS-matched routed GDS** via the layout bounding box, and
   cross-checked against the OpenROAD final area report. Both numbers are
   recorded; the GDS bbox is the claimed one.
2. **The comparison set** a size claim must name:
   - **SERV minimal config synthesized in *this* repo's flow on sky130** —
     the apples-to-apples anchor, from the same pinned tree, synthesized
     and routed by the same commands, published beside the MCU number.
     (SERV's own 2.1kGE figure is quoted only as *their* number, with its
     "excluding register file" caveat attached.)
   - **Commercial 8-pin MCUs, published-die-area only** (e.g. the
     r/nicechips parts in the README), each cited to its datasheet — never
     estimated, never compared against a different measurement method
     without saying so.
3. **Reproducibility: the command path.** Every published area figure cites
   (a) the flow commands from a clean checkout — synthesis,
   place-and-route, and the `klt` DRC/LVS steps as driven from `flow/`
   (the exact request/command path is named by the flow issue that builds
   it), (b) the
   report file paths in `verification/records/` and `layout/`, and (c) the
   tool/PDK pins in force. A figure without its command path is not a
   result; recorded results are append-only evidence.
4. **AREA row targets** (unchanged from the draft, now method-bound):
   target ≤ **0.10 mm²** post-route core area for the full MCU; fallback
   ≤ **0.15 mm²** for the full target MCU. The ≤ **0.05 mm²** stretch
   must demonstrate the same 256 B capacity, 112 B usable map and enabled
   CSRs with the latch implementation. Publish the configuration and verify
   latch timing, DRC and LVS alongside its measured area. Report the external
   boot flash and board reset source alongside any system comparison.
5. **Claim language rule**: the words "smallest", "world's smallest", or
   any comparative size claim appear in this repo only together with the
   measured post-route area of item 1 and the comparison set of item 2.
   Until then, the README Status block stays `not yet measured` and the
   goal statement in the README is a goal, not a claim.

## Alternatives considered

- **Claiming core-only area** (SERV alone, RAM excluded — what SERV's own
  2.1kGE does). Rejected as *the* claim: the block's whole point is the
  paid-for total, RAM included; core-only is still published as the
  comparison line, clearly labelled.
- **Claiming die area with pads.** Rejected: no pad ring is in scope
  (README); a pad-ring figure would be a different, unbuildable claim
  here. Named explicitly so a later pad-ring variant needs this record
  superseded, not silent reinterpretation.
- **FPGA-equivalent claims (LUT counts).** Rejected: this repo's claim is
  ASIC post-route area; LUT counts are SERV's ecosystem context only.
- **Benchmark-based claims (CoreScore-style).** Rejected: not an area
  method.

## Consequences

- The first synthesis/P&R runs exist to *populate* this method, not to
  tune toward the row; a missed target is recorded and the row is changed
  by a new decision record — never relaxed to make a result pass.
- Measuring area is out of scope for this issue (the flow does not exist
  yet); the README Status block stays `not yet measured` / `spec`.
- The ngspice ROSC measurement of record 0005 and any timing claim follow
  the same append-only command-path rule.
