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

Not being built here: on-chip flash (the open sky130 PDK has none; code is loaded from an external SPI flash or held in a mask ROM), an ADC, and any second peripheral of a kind already present. "Smallest" is not claimed until an area is measured from a clean layout. No RTL, layout or silicon exists yet.

## Built agent-native

Every specification, decision record, testbench, and line of documentation in
this repo is produced by AI agents working from a ratified spec and an
append-only evidence trail — not human-authored work that agents merely
assisted with. Verification is the product: every claim traces to a recorded
result. Where the agents hit friction with the open-source tooling — most often
[klayout-tools](https://github.com/2AMLogic/klayout-tools) — that friction gets
filed as a public issue against the tool itself, so the fix benefits everyone
using sky130, not just this repo.

## Target specification (DRAFT — engineering to ratify, see issue #1)

| Parameter | Target | Stretch |
|---|---|---|
| Instruction set | RV32E base integer, bit-serial datapath | RV32I |
| Core supply | 1.8 V |  |
| Clock | ≥ 16 MHz system clock | ≥ 32 MHz |
| RAM | 256 bytes | 1 KB |
| Program storage | boot from external SPI flash | optional mask ROM |
| GPIO | 6 pins, each input or output |  |
| Peripherals | one timer, one UART |  |
| Compliance | passes the RISC-V architectural tests for the implemented base |  |
| Pin count | 8 |  |
| AREA | ≤ 0.10 mm² core, RAM included | ≤ 0.05 mm² |

## Repo layout

```
flow/          synthesis + place-and-route (Yosys, OpenROAD)
layout/        GDS + DRC/LVS reports (klayout-tools driven)
measurements/  silicon characterization (empty until tape-out)
rtl/           Verilog sources
spec/          ratified spec + decision records
verification/  cocotb testbenches
```

## License

Apache License 2.0 — see [LICENSE](LICENSE).
