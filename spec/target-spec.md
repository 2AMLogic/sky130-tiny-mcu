# Target specification — sky130-tiny-mcu

- **Status**: proposed — ratification is the merge of this PR, after the
  two independent reviews (engineering and market) required by the repo
  instructions; the `Status:` lines of this file and the decision records
  flip to `RATIFIED` **in this PR**, never in a follow-up commit.
- **Decision records**: [0001 core](decisions/0001-core.md) ·
  [0002 memory](decisions/0002-memory.md) ·
  [0003 program storage](decisions/0003-program-storage.md) ·
  [0004 peripherals](decisions/0004-peripherals.md) ·
  [0005 pins](decisions/0005-pins.md) ·
  [0006 size claim](decisions/0006-size-claim.md) ·
  [0007 compliance](decisions/0007-compliance.md).
- Upstream facts carry a source and an access date; a statement marked
  *unverified* was not read from a source at ratification.
- **No-relaxation rule**: agents do not relax a row to make a result pass.
  A missed target is recorded, and the row changes through a new decision
  record — with evidence, never silently.
- **Evidence rule**: recorded results are append-only; a result is
  superseded by a later record that says why, never by deletion.

## Parameter table

One row per draft parameter, each with target, fallback, stretch (where
meaningful), a verification method, and its decision record.

| # | Parameter | Target | Fallback | Stretch | Verification | Record |
|---|---|---|---|---|---|---|
| 1 | Core | SERV 1.4.0, bit-serial (`W=1`), by pinned reference `f200eb2ed7b69ac1c6b8eddd47654522aeee5ce8`, unmodified | none — a different core supersedes record 0001 | QERV `W=4` datapath | cocotb compliance run (row 10) on the RTL; synthesis in this repo's flow | [0001](decisions/0001-core.md) |
| 2 | Instruction set | RV32IZifencei + SERV's CSR subset (`WITH_CSR=1`, `COMPRESSED=0`, `MDU=0`) | `WITH_CSR=0`: RV32IZifencei, no traps — compliance reduces to `I`+`Zifencei` | C (`COMPRESSED=1`); M (external MDU) — each with an area measurement | compliance run (row 10) + cocotb CSR tests against the `serv_csr.v` subset | [0001](decisions/0001-core.md), [0007](decisions/0007-compliance.md) |
| 3 | Core and I/O supply | 1.8 V nominal, shared with reference flash | — | — | LVS supply connectivity, internal STA corners in 0006, board I/O margins within flash ratings in 0003 | [0001](decisions/0001-core.md) |
| 4 | Clock | internal ring oscillator, ≥16 MHz at `tt_025C_1v80` | external clock on gpio0 after boot | 32 MHz nominal | extracted ring startup and period range across PVT, post-route STA at each corner’s shortest supported period with uncertainty | [0005](decisions/0005-pins.md) |
| 5 | RAM | 256 B single-port flop array, 144 B RF and 112 B firmware | 256 B latch implementation, same map | 512 B latch build within 0.10 mm² | RF/bus arbitration, boundary and alias tests, latch timing where applicable, measured area | [0002](decisions/0002-memory.md) |
| 6 | Program storage | external 1.8 V W25Q16JW, SPI 03h copies a 112 B image to address 0 | strap RX low, idle high, train with 0x55, load 112 UART bytes | — (mask ROM costed in 0003) | boot both paths, trace last write to 0x6F before first fetch at 0 and observe firmware result | [0003](decisions/0003-program-storage.md) |
| 7 | GPIO | 4 muxed bits with flash isolated. With flash attached and CS# high, 3 independent GPIO, or 2 with UART TX | external clock consumes gpio0 in each mode | — | flash DO and MCU OE contention check through boot, GPIO handoff and flash reprogramming | [0005](decisions/0005-pins.md) |
| 8 | Peripherals | one 32-bit compare timer and one polled 8N1 TX/RX UART with RX-level auto-baud | — | — | register and IRQ tests, qualify framing, polling and drift per baud rate and retraining interval | [0004](decisions/0004-peripherals.md) |
| 9 | Interrupts | one timer-IRQ line into the core (`i_timer_irq`) + machine traps; UART/GPIO polled | none (`WITH_CSR=0`) | — | cocotb IRQ test; compliance `privilege` run | [0001](decisions/0001-core.md), [0004](decisions/0004-peripherals.md) |
| 10 | Compliance | riscv-arch-test 3.10.0 @ `9bceaf5c02fa1131625bc6228b834e9e884c5801`, riscof/SAIL on simulation memory for I, Zifencei and applicable privilege tests, plus CSR tests | I + Zifencei for the CSR-disabled variant | ACT framework by a new record | archive ISA signatures and exclusions, separately verify both boots and execution on the 112 B firmware map | [0007](decisions/0007-compliance.md) |
| 11 | Pin count & mux | 8 pins including VDD, GND and board-driven reset_n. UART TX shares flash COPI, RX selects boot mode | — | — | test asserted reset from unknown state, 256 ROSC edges to strap sample, loader/core release order and pin ownership | [0005](decisions/0005-pins.md) |
| 12 | AREA | ≤0.10 mm² post-route full MCU including 256 B RAM, DRC/LVS clean | ≤0.15 mm² | ≤0.05 mm² with the full 256 B latch array and 144 B RF | flow reports and routed GDS bounding box, RAM configuration and command path per 0006 | [0006](decisions/0006-size-claim.md) |

## Pin mux

Board reset initializes the MCU before the ring-clocked counter starts.
The loader samples RX after the 256-cycle hold. It keeps the core in reset
until the image is committed. Pin functions and electrical handoff are
specified in records 0003 and 0005.

| Pin | Signal | During boot | After release |
|---|---|---|---|
| 1 | `VDD` | nominal 1.8 V | supply |
| 2 | `GND` | common ground | ground |
| 3 | `flash_sclk` / `gpio0` | SPI clock | GPIO or external clock |
| 4 | `flash_cs_n` / `gpio1` | active-low select | keep high for ordinary GPIO on the attached bus |
| 5 | `flash_copi` / `gpio2` / `uart_tx` | SPI data to flash | GPIO or UART TX |
| 6 | `flash_cipo` / `gpio3` | SPI data from flash | GPIO after flash output disable, input during flash access |
| 7 | `uart_rx` | low strap selects UART loader | console RX |
| 8 | `reset_n` | board/system reset | reset input |

## Memory map

| Region | Base | Size | Contents |
|---|---|---|---|
| Firmware | `0x0000_0000` | 112 B | Entry at 0, image and working storage through `0x6F` inclusive |
| Private RF | `0x0000_0070` | 144 B | High end of shared RAM through `0xFF`, reachable only via the RF port |
| Peripherals | `0x4000_0000` | 4 KB window | UART `0x4000_0000`, timer `0x4000_0100`, GPIO `0x4000_0200` (0004) |

Unmapped addresses read `0` and ignore writes (no error return on the
bit-serial bus).

## What is deliberately not here

No on-chip flash, ADC, or any second peripheral of a kind already present
(README); no mask ROM (rejected, record 0003); no watchdog, PWM, DMA,
debug module, or interrupt controller beyond the single timer line
(record 0004). **No size claim exists yet**: the AREA row is a target, the
README Status block stays `not yet measured`, and the word "smallest"
appears in this repo only with the measured area and comparison set of
record 0006.
