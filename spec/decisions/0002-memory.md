# 0002 — Memory: 256 B single-port standard-cell RAM, register file included

- **Status**: proposed — flips to `RATIFIED` in this PR after the two
  independent reviews (engineering and market) required by the repo
  instructions.
- **Supersedes**: the README draft row "RAM: 256 bytes / Stretch: 1 KB" in
  its implementation-agnostic form; the 1 KB stretch is dropped.
- **Superseded by**: none.
- **Spec rows**: `spec/target-spec.md` row 5 (RAM), § Memory map.

## Context

The draft fixes 256 bytes with a 1 KB stretch but no implementation. SERV's
Servile arrangement (record 0001) puts the GPR + CSR storage, the program
and the data in **one single-port memory**, so the RAM must be sized to hold
the register file too. The candidate implementations on sky130 are a
standard-cell flop array, a latch array, or an SRAM macro. Numbers below are
measured from the installed sky130A PDK on this host
(`open_pdks` commit `c6d73a35f524070e85faff4a6a9eef49553ebc2b`, volare root,
files under `libs.ref/`, read **2026-11-19**); upstream source:
https://github.com/google/skywater-pdk via open_pdks.

| Fact | Value | Source |
|---|---|---|
| D flip-flop `sky130_fd_sc_hd__dfxtp_1` area | 20.0192 µm² | `libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib`, `cell ("sky130_fd_sc_hd__dfxtp_1")` |
| D latch `sky130_fd_sc_hd__dlxtp_1` area | 15.0144 µm² | same file, `cell ("sky130_fd_sc_hd__dlxtp_1")` |
| NAND2 `sky130_fd_sc_hd__nand2_1` area | 3.7536 µm² | same file (basis for the GE→µm² re-reads in 0006) |
| SRAM macro `sram_1rw1r_32_256_8_sky130` (1 kB) | LEF SIZE 376.48 × 446.235 µm = **167,999 µm² ≈ 0.168 mm² — smallest shipped**; the only macro with corner `.lib` coverage (7 files: FF/SS/TT at 1p7/1p8/1p9 V, 0/25/100 °C; the other three ship one TT file each) | `libs.ref/sky130_sram_macros/lef/sram_1rw1r_32_256_8_sky130.lef`, `lib/` listing |
| SRAM macro `sky130_sram_1kbyte_1rw1r_32x256_8` (1 kB) | LEF SIZE 479.78 × 397.5 µm = 190,712 µm² ≈ 0.191 mm² | `libs.ref/sky130_sram_macros/lef/sky130_sram_1kbyte_1rw1r_32x256_8.lef` |
| SRAM macro `sky130_sram_1kbyte_1rw1r_8x1024_8` (1 kB) | LEF SIZE 455.3 × 446.46 µm ≈ 0.203 mm² | `libs.ref/sky130_sram_macros/lef/sky130_sram_1kbyte_1rw1r_8x1024_8.lef` |
| SRAM macro `sky130_sram_2kbyte_1rw1r_32x512_8` (2 kB) | LEF SIZE 683.1 × 416.54 µm ≈ 0.285 mm² | `libs.ref/sky130_sram_macros/lef/sky130_sram_2kbyte_1rw1r_32x512_8.lef` |
| SRAM macro inventory complete | the four rows above are the complete LEF listing of `libs.ref/sky130_sram_macros/lef/` — no fifth macro, none unlisted | directory listing, 2026-11-19 |
| No ROM macro | `libs.ref/` contains `sky130_fd_io`, `sky130_fd_pr`, `sky130_fd_sc_hd`, `sky130_fd_sc_hvl`, `sky130_ml_xx_hd`, `sky130_sram_macros`; none is a ROM (also feeds record 0003) | directory listing, 2026-11-19 |

Area arithmetic from the cell areas above (raw cell area; routing and
utilization overhead come on top and are measured by the flow, never
assumed):

| Configuration | Bits | Raw cell area, flops (dfxtp_1) | Raw cell area, latches (dlxtp_1) |
|---|---|---|---|
| Register file (16 × 32 b) | 512 | 0.010 mm² | 0.008 mm² |
| 128 B | 1,024 | 0.021 mm² | 0.015 mm² |
| **256 B (target)** | 2,048 | **0.041 mm²** | 0.031 mm² |
| 512 B | 4,096 | 0.082 mm² | 0.062 mm² |
| 1 KB (draft stretch) | 8,192 | **0.164 mm²** | 0.123 mm² |

The AREA row budget is ≤ 0.10 mm² (draft row, kept). A 1 KB flop array alone
is 0.164 mm² of raw cells — more than the whole budget — so the draft's
1 KB stretch is arithmetically unreachable and is dropped rather than
carried as a dead row.

## Decision

1. **RAM: 256 bytes, single port, one array** holding the register file
   (GPRs + SERV's CSR storage, Servile arrangement, record 0001) and the
   program + data. User-visible program+data is the remaining 192 B after
   the RF region.
2. **Implementation: standard-cell flop array** synthesized from generated
   RTL (a wrapper around SERV's own `serv_rf_ram` memory side; the RF-in-RAM
   glue is exactly what the pinned Servile wrapper provides). The flop
   choice follows from the table: the target size costs ≈ 0.041 mm² raw
   cells, the single affordable point on the ladder.
3. **Memory map** (matches SERV/Servile's split — `doc/servile.rst`: memory
   below `0x40000000`, external accesses above):

   | Region | Base | Size | Contents |
   |---|---|---|---|
   | RAM (RF + program + data) | `0x0000_0000` | 256 B | RF region first (`0x0000_0000`–`0x0000_003F`), then program/data |
   | Peripherals | `0x4000_0000` | 4 KB window | UART, timer, GPIO — maps in record 0004 |

   Reset vector `RESET_PC = 0x0000_0000` (SERV parameter, record 0001), so
   the boot copy lands at the fetch address (record 0003).
4. **Fallback: 128 B** (0.021 mm² raw), taken only by a new decision record
   if the measured post-route area of the 256 B build misses the AREA row.
5. **Stretch: 512 B, latch-based** (0.062 mm² raw), only if a measured
   post-route build stays within the AREA row; latches need scan/clock
   discipline work in the flow, so this is measured, not assumed.

## Alternatives considered

- **SRAM macro** (1 KB `sky130_sram_1rw1r` or larger). Rejected with the
  measured LEF sizes: the smallest shipped macro
  (`sram_1rw1r_32_256_8_sky130`) is 0.168 mm² — 1.68× the entire AREA
  budget — and it is 4× the target capacity. The sibling repo's
  macro-based SoC can afford this because its budget is 3.8 mm²; this
  block's is 0.10 mm².
- **Latch array at 256 B as the target.** Rejected for the target row, kept
  as the 512 B stretch vehicle: dlxtp_1 saves ≈ 25 % of the array raw area
  but needs transparent-latch timing discipline in the flow before it can
  be trusted; the flop array reaches the target with standard
  positive-edge-triggered timing.
- **Split RF (own array) + 256 B main RAM.** Rejected: adds ≈ 0.010 mm² of
  flops and a second memory port for no capacity gain; the Servile
  single-array arrangement is the pinned upstream's own ASIC pattern
  (Subservient: "single-port SRAM for SERV's register file, data and
  instruction memories").
- **1 KB stretch.** Dropped with the arithmetic above (0.164 mm² raw flops
  > 0.10 mm² budget).

## Consequences

- Program + data budget is **192 B** — this, not the RAM row alone, is the
  binding software constraint, and it feeds record 0003 (boot) and 0007
  (compliance harness sizing).
- Register accesses take memory cycles (bit-serial RF through the shared
  array), deepening SERV's already-large cycle counts; accepted, since the
  block's performance contract is "control tasks at ≥ 16 MHz", not MIPS.
- The array is generated RTL and verified by the cocotb memory testbench;
  its measured area lands in the flow reports that record 0006 consumes.
