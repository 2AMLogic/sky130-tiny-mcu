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

1. **AREA grades the routed placement core of the full MCU.** Use the
   top-level `core_area_um2` in the final `klt place-and-route` report.
   It measures the core floorplan, including whitespace, for the design
   containing SERV, RAM, clock ring, boot logic and peripherals. Require
   a clean DRC and matching LVS for the same routed layout. Report the
   padless die footprint (`die_area_um2`) separately. Also record the
   bounding box of the routed GDS top cell as the extent of drawn geometry.
   Pins and routing can extend beyond the placement core.
2. **The comparison set** a size claim must name:
   - **SERV minimal config synthesized in *this* repo's flow on sky130** —
     the apples-to-apples anchor, from the same pinned tree, synthesized
     and routed by the same commands. Extract `core_area_um2` by the same
     rule in item 1 and publish it beside the MCU core area.
     (SERV's own 2.1kGE figure is quoted only as *their* number, with its
     "excluding register file" caveat attached.)
   - **Commercial 8-pin MCUs, published-die-area only** (e.g. the
     r/nicechips parts in the README), each cited to its datasheet. Use
     the MCU's separate die figure for this comparison and disclose the
     padless boundary and the commercial part's pad inclusion where known.
3. **Extract and grade the area.** From the repo root, the following
   commands use the [committed smoke report](../../verification/records/flow-smoke/20261122T213813Z-7fb324c8f0fe6f3159a1d3e87b6e3875cf537620/place-and-route.json)
   as a worked example. For the MCU or SERV, set `report` to that build's
   archived final report. The first command on the report prints both
   footprints in µm². The second exits successfully only when the routed
   core meets the selected limit. Use 100000 µm² for target, 150000 for
   fallback and 50000 for stretch (1 mm² = 1,000,000 µm²).

   ```sh
   report=verification/records/flow-smoke/20261122T213813Z-7fb324c8f0fe6f3159a1d3e87b6e3875cf537620/place-and-route.json
   jq '{core_area_um2, die_area_um2}' "$report"
   jq -e --argjson limit_um2 100000 '
     select(.status == "ok" and .stage_reached == "route")
     | .core_area_um2 | numbers | . > 0 and . <= $limit_um2
   ' "$report"
   ```

   The smoke counter reports 1506.44 µm² of core and 3600 µm² of die.
   Its clock pin at x = 0.4 µm lies outside the [requested core](../../flow/smoke/par.json),
   whose left edge is at 10 µm. These figures demonstrate the extraction
   method. For a design claim, archive the build configuration, flow
   requests and commands, tool/PDK pins, routed report, GDS and signoff
   report paths so the measurement can be reproduced from a clean checkout.
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
- The first MCU measurement requires its own routed build and signoff.
  The README Status block stays `not yet measured` / `spec` until then.
- The ngspice ROSC measurement of record 0005 and any timing claim follow
  the same append-only command-path rule.
