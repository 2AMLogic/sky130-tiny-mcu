# 0003 — Program storage: SPI-flash copy-boot at reset, flash pins become GPIO

- **Status**: proposed — flips to `RATIFIED` in this PR after the two
  independent reviews (engineering and market) required by the repo
  instructions.
- **Supersedes**: the README draft row "Program storage: boot from external
  SPI flash / Stretch: optional mask ROM"; the mask-ROM stretch is dropped
  with its cost stated.
- **Superseded by**: none.
- **Spec rows**: `spec/target-spec.md` row 6 (Program storage).

## Context

The open sky130 PDK has no on-chip non-volatile memory (README § Status, and
record 0002's `libs.ref/` listing shows no ROM library), so program storage
is either external or a synthesized read-only array. The draft chose
"boot from external SPI flash" with a mask-ROM stretch, but did not fix the
protocol, the boot mechanism, or the mask-ROM cost. Facts read
**2026-11-19** unless noted.

| Fact | Value | Source |
|---|---|---|
| sky130 ROM macro | none shipped | `libs.ref/` listing, PDK commit `c6d73a35…` (record 0002) |
| Synthesized ROM cost | a 256 B ROM is a 2,048-bit constant array; the read path alone is of the same order as the flop RAM of record 0002 (≈ 0.03–0.04 mm² raw cells before decode/write-path savings) | arithmetic on the cell areas of record 0002 — **estimate**, marked as such; the point stands that it is paid in area |
| SPI flash READ command | `03h`: command + 24-bit address, data clocked out continuously while CS is low (mode 0) | the command is implemented identically by every commodity serial-flash family (25-series datasheets); *unverified against one specific datasheet here* — the cocotb boot testbench pins the exact timing against the flash model chosen by the RTL issue |
| Pin arithmetic | 8-pin package − VDD − GND = 6 signal pins; SPI flash (4) + UART (2) = 6 → flash and GPIO must share pins (record 0005) | record 0005 pin table |
| Precedent for a tiny boot FSM | the sibling SoC uses a 4 KB boot ROM whose firmware copies/receives code into SRAM (`spec/soc.md` § Memory map, read 2026-11-19); this block has no room for a firmware ROM, so the copy is hardware | 2AMLogic/sky130-riscv-soc @ `e1135913b57ebf0cd57a7882772545fedb7291d0` |

The binding question: after boot, do the four flash pins stay busy (XIP) or
become GPIOs? A GPIO-less MCU on 8 pins is not a useful microcontroller, and
SERV/XIP would hold the bus for every instruction fetch (bit-serial core =
dense fetch traffic). The draft's "6 GPIO" is impossible in any external-
storage arrangement (record 0005); the reachable goal is **persistent
program + 4 GPIOs**, which is exactly what a copy-boot gives.

## Decision

1. **Target: hardware copy-boot from external SPI flash.** At reset exit
   (the instant defined in record 0005 § Decision 6), a
   small boot FSM issues one `03h` READ of the full 256 B RAM image from
   flash address `0x000000` into the RAM of record 0002 (mode 0: CPOL=0,
   CPHA=0), deasserts CS, and only then releases the core from reset
   (`RESET_PC = 0`). The FSM is new RTL owned by this repo (SERV ships no
   flash controller); its area is charged to the AREA row and measured by
   the flow — **estimate**: a byte-serial SPI master of this size is a few
   hundred GE (≈ 0.001–0.002 mm²); the first synthesis run replaces this
   estimate.
2. **After boot, pins 3–6 are GPIOs** (record 0005 mux). The MCU can
   reprogram its own flash by bit-banging the flash pins from software
   through the GPIO block; the boot FSM never runs again until reset.
3. **Fallback: UART load-to-RAM boot (development mode).** Strap: if
   `uart_rx` is sampled **low** at reset exit, the boot FSM is skipped and
   a hardware UART loader takes over: it measures the low time of the first
   rx pulse to derive the bit period (host sends `0x55` first — start bit
   low time = one bit period), then receives 256 raw bytes into RAM at
   `0x0000_0000` and releases the core. No persistent program in this mode;
   it exists so a blank part is bring-up-able and so compliance firmware
   (record 0007) can be loaded without a flash model in the loop.
4. **Mask ROM: dropped.** Cost of keeping it: (a) area — a synthesized
   256 B constant array is paid exactly like the flop RAM of record 0002
   but buys nothing a 40-cent serial flash does not; (b) one firmware per
   mask set — every program change is a new mask revision of a die that was
   supposed to be a catalog part; (c) no ROM macro exists in the open PDK,
   so it would be hand-grown RTL forever. Rejected on all three counts.
5. **Blank-flash behavior**: the FSM always completes the copy and releases
   the core; a blank (all-`FF`) image leaves the core executing `FF`
   words. The spec does not promise more; the RTL issue may refine (e.g.
   signature check jumping to the UART loader) by record, not by silence.

## Alternatives considered

- **XIP from SPI flash** (fetch every instruction over SPI, Servant-style).
  Rejected: the four flash pins are then never free, so GPIO = 0 and the
  8-pin part loses its only general-purpose I/O; fetch latency also
  multiplies SERV's cycle counts.
- **Mask ROM** (draft stretch). Dropped — costed and rejected above.
- **Firmware boot loader in a small ROM** (the sibling SoC's pattern).
  Rejected: the RAM is 256 B total (record 0002); a loader firmware living
  beside the user program would consume the program budget. The loader is
  hardware here.
- **UART boot as the only mode** (no flash). Rejected: no persistent
  program — the part stops being usable untethered, which is the point of
  an MCU.
- **QSPI / fast-read commands (`0Bh`, dual/quad).** Rejected for the
  target: wider buses cost pins this package does not have; `03h` is the
  universal baseline every flash implements.

## Consequences

- The boot FSM, the strap mux and the pin mux (record 0005) are one
  coherent RTL unit; their combined area is measured in the flow reports.
- Boot latency is the `03h` read time of 256 B at whatever clock the FSM
  drives (a flow/RTL choice, measured, not specified here).
- The cocotb boot testbench exercises: flash boot (against a SPI flash
  model), UART boot (auto-baud + raw load), and the pin release to GPIO
  after each mode.
