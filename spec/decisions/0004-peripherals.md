# 0004 — Peripherals: one timer, one UART; an explicit absent-list

- **Status**: proposed — flips to `RATIFIED` in this PR after the two
  independent reviews (engineering and market) required by the repo
  instructions.
- **Supersedes**: the README draft row "Peripherals: one timer, one UART"
  in its unenumerated form.
- **Superseded by**: none.
- **Spec rows**: `spec/target-spec.md` row 8 (Peripherals), § Memory map.

## Context

The draft fixes "one timer, one UART" but no register map and no explicit
statement of what is deliberately absent. The repo instructions require that
no register, peripheral or debug feature be included without an area
justification — so the absent-list is part of the decision, not a footnote.
Two ecosystem facts frame the choice (read **2026-11-19** at the pinned
commit, record 0001):

- SERV with `WITH_CSR=1` exposes exactly one interrupt input,
  `i_timer_irq`, and "only implements a small subset of the CSR registers"
  (`doc/interface.rst`, `doc/servile.rst`). Any peripheral beyond polling
  needs to fit that single line or add core-adjacent RTL this repo does not
  own.
- SERV's own FPGA reference (Servant) ships "SERV, a timer, memory and a
  1-bit GPIO output pin" and bit-bangs its UART from software
  (`doc/servant.rst`) — the ecosystem precedent is that even the UART is
  optional glue. This repo makes the UART hardware because its boot
  fallback (record 0003) needs a receiver while the RAM is empty.

## Decision

1. **Timer: one 32-bit free-running up-counter** at the system clock, with
   one 32-bit compare register whose match asserts the core's
   `i_timer_irq`. No capture input, no prescaler, no second channel.
   Software timing/auto-baud (below) reads the counter directly.
2. **UART: one instance, 8N1, TX + RX**, programmable 16×-oversample-style
   divisor; the RX line level is readable as one status bit so software can
   measure the incoming bit period with the timer **before** a divisor is
   programmed (host auto-baud, runtime). TX/RX are polled; the UART raises
   no interrupt. TX pacing is by the **tx-ready status bit** (below), so
   polled TX never needs open-loop timing against an uncalibrated clock.
3. **GPIO: 4 bits** (the post-boot flash pins of record 0005), per-pin
   output enable, output register, input register with a 2-FF synchronizer.
   No per-pin interrupts.
4. **Register map** (peripheral window `0x4000_0000`–`0x4000_0FFF`,
   record 0002; unmapped addresses read `0` and ignore writes — never hang,
   the bit-serial bus has no error return):

   | Offset | Block | Register | Width | Notes |
   |---|---|---|---|---|
   | `0x4000_0000` | UART | `DATA` | 8 | write = TX byte, read = RX byte (RX overruns lost) |
   | `0x4000_0004` | UART | `STATUS` | 3 | bit0 rx level (auto-baud), bit1 rx byte ready, bit2 tx ready (shift register idle — write `DATA` only when set) |
   | `0x4000_0008` | UART | `DIVISOR` | 16 | system-clock cycles per bit |
   | `0x4000_0100` | timer | `COUNT` | 32 | free-running, read-only |
   | `0x4000_0104` | timer | `COMPARE` | 32 | match ⇒ `i_timer_irq` until next write |
   | `0x4000_0200` | GPIO | `OUT` | 4 | |
   | `0x4000_0204` | GPIO | `OE` | 4 | 1 = output |
   | `0x4000_0208` | GPIO | `IN` | 4 | synchronized inputs |

   (Offsets are word-aligned byte offsets; this is the contract the cocotb
   peripheral testbenches and the firmware build are written against.)
5. **Deliberately absent** — each absence is the area decision:
   - **Watchdog / second timer** — any WDT is a second timer; the block's
     size claim is the product, so exactly one.
   - **PWM outputs** — software can toggle GPIOs from the timer.
   - **ADC/DAC/analog anything** — this repo is a digital block with no
     analog half by charter (README).
   - **SPI/I²C slave, second SPI master** — flash reprogramming bit-bangs
     GPIOs (record 0003); an I²C device can be emulated in software if an
     application ever needs one.
   - **DMA** — no bus fabric to arbitrate; the Servile memory port is
     single.
   - **Debug module (JTAG/SWD/RISC-V DM)** — no pins exist for a TAP
     (record 0005); debug is the UART console. SERV ships no debug module.
   - **Vectored interrupt controller / UART or GPIO IRQ lines** — the core
     has one interrupt input (record 0001); everything else polls.
   - **Clock gating / power-management unit** — out of scope for a
     0.10 mm² digital canary; the clock is one root (record 0005).

## Alternatives considered

- **UART interrupt line**. Rejected: `i_timer_irq` is the core's only
  interrupt input; muxing a second source in would be a local core-adjacent
  addition with no area budget line. Polling from a control loop is
  adequate at these baud rates.
- **Timer capture input for hardware auto-baud**. Rejected for the target:
  the RX-level status bit + timer read achieves the same measurement in
  software; the hardware UART loader of record 0003 already contains the
  one place auto-baud genuinely must be hardware (empty RAM at boot).
- **More GPIOs by dropping the UART**. Rejected: the UART is the
  programming and debug surface (records 0003/0005); a GPIO-only part is
  unbringup-able.
- **Matching the sibling repo's peripheral richness** (boot ROM, OBI
  crossbar, 8-bit GPIO, 64-bit machine timer). Rejected: that repo's budget
  is 3.8 mm² and its goal is integration tooling surface; this repo's goal
  is the area row.

## Consequences

- Peripheral area is small but nonzero and lands in the flow reports that
  feed the AREA row; no peripheral exists that is not in this record.
- The register map above is frozen by ratification; changes are new
  decision records, so firmware written against it stays valid.
- The compliance firmware (record 0007) targets exactly these registers
  plus the RAM map of record 0002.
