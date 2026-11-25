# sky130-tiny-mcu

A Tiny RISC-V microcontroller on the [sky130](https://github.com/google/skywater-pdk) open PDK,
designed by AI agents driving
[klayout-tools](https://github.com/2AMLogic/klayout-tools) and the open-source
flow — cocotb + Icarus for verification, Yosys and OpenROAD for implementation.

The goal is the smallest useful open microcontroller: a bit-serial RISC-V core, a small RAM, a few GPIO pins, a timer and a serial port, on a die small enough for an 8-pin package.

**Where the idea came from.** Tiny, nearly free microcontrollers are the parts engineers get most excited about. This repo asks how small an open one can be made, and publishes the measured answer with the method. The prompt was a post on r/nicechips, a forum where engineers share parts they admire: [the "world's smallest MCU"](https://www.reddit.com/r/nicechips/comments/1ja0po2/ti_mspm0c1104_worlds_smallest_mcu_is_16mm_x/); [a sub-10-cent Cortex-M0+](https://www.reddit.com/r/nicechips/comments/10uam3r/sub_01_cortexm0_py32_series_from_puya/); [the 3-cent microcontroller](https://www.reddit.com/r/nicechips/comments/9nkipp/eevblog_1132_the_3_cent_microcontroller/). This repo is an original design of the same kind of part, not a copy of the one in the post.

## Status

```
Area (measured, post-layout): not yet measured
Design stage: spec
```

<!-- The two fields above are correct as they stand for a repo where nothing is
     built yet, so there is nothing to fill in here — only to keep current. They
     are a fixed-location summary a chip-level integrator reads without parsing
     the prose below, so the keys, their spelling, and their order do not change.

     Area (measured, post-layout): the as-built area of a DRC-clean,
     LVS-matched layout, as a number with units (e.g. 1.059 mm²), taken from
     this repo's own committed measurement. Never a target, a plan, or an
     estimate — the ratified bound is the AREA row of the target-specification
     table below. Until a layout exists, the literal "not yet measured".

     Design stage: exactly one token, from this ladder, in order —
     spec | schematic-sim | layout-DRC-LVS-clean | extracted-verified | silicon
     — describing what this repo has produced and recorded evidence for, never
     what it is aiming at. One token; not a range, not a hedge, not prose. -->

**Just opened, specification phase.** Nothing is designed yet, nothing has been
taped out, and nothing has been measured.

Not being built here: on-chip flash (the open sky130 PDK has none; the program is copied from an external SPI flash at boot, decision record [0003](spec/decisions/0003-program-storage.md)), an ADC, and any second peripheral of a kind already present. "Smallest" is not claimed until an area is measured from a clean layout. No RTL, layout or silicon exists yet.

## Built agent-native

Every specification, decision record, testbench, and line of documentation in
this repo is produced by AI agents working from a ratified spec and an
append-only evidence trail — not human-authored work that agents merely
assisted with. Verification is the product: every claim traces to a recorded
result. Where the agents hit friction with the open-source tooling — most often
[klayout-tools](https://github.com/2AMLogic/klayout-tools) — that friction gets
filed as a public issue against the tool itself, so the fix benefits everyone
using sky130, not just this repo.

## Target specification (proposed — see [spec/target-spec.md](spec/target-spec.md))

| # | Parameter | Target | Fallback | Stretch | Verification | Record |
|---|---|---|---|---|---|---|
| 1 | Core | SERV 1.4.0, bit-serial (`W=1`), by pinned reference `f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8`, unmodified | none — a different core supersedes record 0001 | QERV `W=4` datapath | cocotb compliance run (row 10) on the RTL; synthesis in this repo's flow | [0001](spec/decisions/0001-core.md) |
| 2 | Instruction set | RV32IZifencei + SERV's CSR subset (`WITH_CSR=1`, `COMPRESSED=0`, `MDU=0`) | `WITH_CSR=0`: RV32IZifencei, no traps — compliance reduces to `I`+`Zifencei` | C (`COMPRESSED=1`); M (external MDU) — each with an area measurement | compliance run (row 10) + cocotb CSR tests against the `serv_csr.v` subset | [0001](spec/decisions/0001-core.md), [0007](spec/decisions/0007-compliance.md) |
| 3 | Core and I/O supply | 1.8 V nominal, shared with reference flash | — | — | LVS supply connectivity, internal STA corners in 0006, board I/O margins within flash ratings in 0003 | [0001](spec/decisions/0001-core.md) |
| 4 | Clock | internal ring oscillator, ≥16 MHz at `tt_025C_1v80` | external clock on gpio0 after boot | 32 MHz nominal | extracted ring startup and period range across PVT, post-route STA at each corner’s shortest supported period with uncertainty | [0005](spec/decisions/0005-pins.md) |
| 5 | RAM | 256 B single-port flop array, 144 B RF and 112 B firmware | 256 B latch implementation, same map | 512 B latch build within 0.10 mm² | RF/bus arbitration, boundary and alias tests, latch timing where applicable, measured area | [0002](spec/decisions/0002-memory.md) |
| 6 | Program storage | external 1.8 V W25Q16JW, SPI 03h copies a 112 B image to address 0 | strap RX low, idle high, train with 0x55, load 112 UART bytes | — (mask ROM costed in 0003) | boot both paths, trace last write to 0x6F before first fetch at 0 and observe firmware result | [0003](spec/decisions/0003-program-storage.md) |
| 7 | GPIO | 4 muxed bits with flash isolated. With flash attached and CS# high, 3 independent GPIO, or 2 with UART TX | external clock consumes gpio0 in each mode | — | flash DO and MCU OE contention check through boot, GPIO handoff and flash reprogramming | [0005](spec/decisions/0005-pins.md) |
| 8 | Peripherals | one 32-bit compare timer and one polled 8N1 TX/RX UART with RX-level auto-baud | — | — | register and IRQ tests, qualify framing, polling and drift per baud rate and retraining interval | [0004](spec/decisions/0004-peripherals.md) |
| 9 | Interrupts | one timer-IRQ line into the core (`i_timer_irq`) + machine traps; UART/GPIO polled | none (`WITH_CSR=0`) | — | cocotb IRQ test; compliance `privilege` run | [0001](spec/decisions/0001-core.md), [0004](spec/decisions/0004-peripherals.md) |
| 10 | Compliance | riscv-arch-test 3.10.0 @ `9bceaf5c02fa1131625bc6228b834e9e884c5801`, riscof/SAIL on simulation memory for I, Zifencei and applicable privilege tests, plus CSR tests | I + Zifencei for the CSR-disabled variant | ACT framework by a new record | archive ISA signatures and exclusions, separately verify both boots and execution on the 112 B firmware map | [0007](spec/decisions/0007-compliance.md) |
| 11 | Pin count & mux | 8 pins including VDD, GND and board-driven reset_n. UART TX shares flash COPI, RX selects boot mode | — | — | test asserted reset from unknown state, 256 ROSC edges to strap sample, loader/core release order and pin ownership | [0005](spec/decisions/0005-pins.md) |
| 12 | AREA | ≤0.10 mm² post-route full MCU including 256 B RAM, DRC/LVS clean | ≤0.15 mm² | ≤0.05 mm² with the full 256 B latch array and 144 B RF | flow reports and routed GDS bounding box, RAM configuration and command path per 0006 | [0006](spec/decisions/0006-size-claim.md) |

## Repo layout

```
flow/          synthesis + place-and-route (Yosys, OpenROAD)
layout/        GDS + DRC/LVS reports (klayout-tools driven)
measurements/  silicon characterization (empty until tape-out)
rtl/           Verilog sources
spec/          ratified spec + decision records
verification/  cocotb testbenches
WORK_LOG.md    merged PRs / closed issues (Guide-maintained)
WORK_PLAN.md   backlog snapshot from label state (Guide-maintained)
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
