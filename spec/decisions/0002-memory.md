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
Servile wrapper exposes register-file (RF) and memory ports. This design
combines them in one array using the adapter below, following the upstream
Subservient single-memory design. The candidate implementations on sky130 are a
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
| RF within target array (32 GPR + 4 CSR slots, 32 bits each) | 1,152 | 0.0231 mm² | 0.0173 mm² |
| 128 B (too small for the RF) | 1,024 | 0.021 mm² | 0.015 mm² |
| **256 B (target)** | 2,048 | **0.041 mm²** | 0.031 mm² |
| 512 B | 4,096 | 0.082 mm² | 0.062 mm² |
| 1 KB (draft stretch) | 8,192 | **0.164 mm²** | 0.123 mm² |

The AREA row budget is ≤ 0.10 mm² (draft row, kept). A 1 KB flop array alone
is 0.164 mm² of raw cells — more than the whole budget — so the draft's
1 KB stretch is arithmetically unreachable and is dropped rather than
carried as a dead row.

## Decision

1. **One 256 × 8 single-port flop array.** Configure upstream `servile`
   with `width=1`, `rf_width=8`, `with_csr=1`, `reset_pc=0`.
   It exposes the RF port of `serv_rf_ram_if` and the arbitrated instruction/data
   bus. Connect both to `servile_rf_mem_if` with `depth=256`, `rf_regs=36`.
   On an enabled read, register the addressed byte. On writes and idle
   cycles, hold the last read byte. The adapter can stall partway through
   a word fetch for an RF write and still needs the previously read byte.
   Test consecutive CSR instructions that stall a fetch, assert mutually
   exclusive read/write enables, and check for one array in synthesis. The
   boot mux owns the write port while the core is held in reset.
2. **Physical address allocation.** The RF has 32 GPR slots (including x0)
   plus four CSR storage slots. At four bytes each it occupies 144 B.
   The adapter complements the zero-extended RF byte index. With eight
   address bits, indices 0 through 143 map from `0xFF` down to `0x70`.
   A CPU word access uses its ordinary little-endian byte addresses.

   | Region | First byte | Last byte | Use |
   |---|---|---|---|
   | Firmware | `0x00` | `0x6F` | 112 B for instructions, constants, data, BSS and downward-growing stack together. Entry at 0. Initial stack top may be 0x70 (exclusive). |
   | Private RF | `0x70` | `0xFF` | 144 B accessible on the RF port. Boot writes and CPU bus accesses are excluded. |
   | Peripherals | `0x4000_0000` | `0x4000_0FFF` | Word-aligned registers in record 0004. |

   The MCU wrapper decodes the full bus address before truncating it for the
   adapter. A bus access outside firmware or an implemented register is
   acknowledged, reads zero and discards writes. This prevents an alias of
   the RF or low RAM. The linker must fit the whole firmware working set.
   Reset sets the PC to 0. Firmware initializes registers and trap state
   before use. The RF need not be cleared by the loader, and x0 reads zero.
3. **Fallback implementation.** A 256 B latch array keeps the same RF,
   image and software map. Use it only with verified latch timing and a
   measured layout. A 128 B array is 16 B short of the RF alone.
4. **Capacity stretch.** A 512 B latch build must meet the 0.10 mm² target.
   The complemented RF indices occupy `0x170–0x1FF`, leaving 368 B below.
   Its boot image fills that larger firmware region. For the separate
   CSR-disabled variant, keep the same firmware boundary and reserve the
   16 unused RF bytes so that its boot format stays compatible.

The sizing and translation follow the pinned RTL, read 2026-11-25.
[Servile parameters](https://github.com/olofk/serv/blob/f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8/servile/servile.v),
[RF size](https://github.com/olofk/serv/blob/f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8/rtl/serv_rf_ram.v),
[byte-address arbitration](https://github.com/olofk/serv/blob/f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8/servile/servile_rf_mem_if.v),
[Serving integration example](https://github.com/olofk/serv/blob/f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8/serving/serving.v).

## Alternatives considered

- **SRAM macro** (1 KB `sky130_sram_1rw1r` or larger). Rejected with the
  measured LEF sizes: the smallest shipped macro
  (`sram_1rw1r_32_256_8_sky130`) is 0.168 mm² — 1.68× the entire AREA
  budget — and it is 4× the target capacity. The sibling repo's
  macro-based SoC can afford this because its budget is 3.8 mm²; this
  block's is 0.10 mm².
- **Latch array at 256 B as the target.** Rejected for the target row, kept
  as the fallback and for the 512 B stretch. The dlxtp_1 saves about 25%
  of raw storage area. Its transparent phase needs timing verification.
- **Split RF (own array) + 256 B main RAM.** Rejected: adds ≈ 0.0231 mm² of
  storage flops to gain 144 B of firmware capacity. The shared adapter
  allows one physical array to serve both ports within the area budget.
- **1 KB stretch.** Dropped with the arithmetic above (0.164 mm² raw flops
  > 0.10 mm² budget).

## Consequences

- Program + data budget is **112 B** — this, not the RAM row alone, is the
  binding software constraint, and it feeds record 0003 (boot) and 0007
  (production-map execution check).
- Register accesses take memory cycles (bit-serial RF through the shared
  array), deepening SERV's already-large cycle counts; accepted, since the
  block's performance contract is "control tasks at ≥ 16 MHz", not MIPS.
- The array is generated RTL and verified by the cocotb memory testbench;
  its measured area lands in the flow reports that record 0006 consumes.
