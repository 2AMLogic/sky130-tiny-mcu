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
| 3 | Core supply | 1.8 V (`sky130_fd_sc_hd` nominal) | — | — | LVS power hooks; STA at the 1v80 corners of record 0006 | [0001](decisions/0001-core.md) |
| 4 | Clock | internal ring oscillator, ≥ 16 MHz at `tt_025C_1v80` | external clock applied on `gpio0` (software-selected mux) | 32 MHz nominal (shorter ring) | post-route STA closes 16 MHz; ROSC frequency + variance across the PDK corners recorded from an ngspice run, append-only | [0005](decisions/0005-pins.md) |
| 5 | RAM | 256 B, single port, one array: register file + program + data; standard-cell flops | 128 B, by a new record if the AREA row is missed | 512 B, latch-based, only if a measured build stays ≤ 0.10 mm² | cocotb memory testbench (RF, program, data); area from the flow reports feeding record 0006 | [0002](decisions/0002-memory.md) |
| 6 | Program storage | hardware copy-boot: SPI flash `03h` READ of 256 B into RAM at reset, then core release (`RESET_PC=0`); flash pins become GPIO | UART load-to-RAM boot (strap `uart_rx` low at reset exit; HW auto-baud + 256 raw bytes) | — (mask ROM rejected — costed in the record) | cocotb boot testbenches: flash model boot, UART boot, pin release to GPIO | [0003](decisions/0003-program-storage.md) |
| 7 | GPIO | 4 bits (pins 3–6, muxed with flash, released at boot end) | 3 bits (when `gpio0` is the external-clock fallback) | — | cocotb pin-mux testbench; the pin table sums to 8 | [0005](decisions/0005-pins.md) |
| 8 | Peripherals | one timer (32-bit up-counter, compare → IRQ) + one UART (8N1, TX/RX, polled, SW auto-baud via RX-level bit); absent-list in the record | — | — | cocotb per-peripheral testbenches against the register map of the record | [0004](decisions/0004-peripherals.md) |
| 9 | Interrupts | one timer-IRQ line into the core (`i_timer_irq`) + machine traps; UART/GPIO polled | none (`WITH_CSR=0`) | — | cocotb IRQ test; compliance `privilege` run | [0001](decisions/0001-core.md), [0004](decisions/0004-peripherals.md) |
| 10 | Compliance | riscv-arch-test **3.10.0** @ `9bceaf5c02fa1131625bc6228b834e9e884c5801` (`old-framework-3.x`), riscof + SAIL-RISCV golden model; suites `rv32i_m/I`, `Zifencei`, `privilege`; CSR subset via cocotb tests | `I`+`Zifencei` only (the `WITH_CSR=0` fallback of row 2) | move to the ACT framework, by a record | recorded compliance run in `verification/records/` with all pins | [0007](decisions/0007-compliance.md) |
| 11 | Pin count & mux | 8 pins: VDD, GND, 4 × flash/gpio, uart_rx (boot strap), uart_tx — table in the record | — | — | cocotb pin-mux testbench; package pinout review against the record's table | [0005](decisions/0005-pins.md) |
| 12 | AREA | ≤ 0.10 mm² post-route core area (RAM included), DRC/LVS-clean | ≤ 0.15 mm² | ≤ 0.05 mm² — the record-0002 latch/128 B build, and labelled as such wherever quoted | the measurement method of record 0006: flow reports + GDS bbox on the clean layout, command path cited | [0006](decisions/0006-size-claim.md) |

## Pin mux

Pins 1–2 are supply; pins 3–6 carry the boot-time flash interface and
become GPIOs when the boot FSM releases them; pin 7 doubles as the boot
strap. Reset is generated on-chip — no reset pin exists: a ROSC-clocked
release counter holds the part in reset for its first 256 ROSC cycles, and
`uart_rx` is sampled once at reset exit (record 0005 § Decision 6). Full
table and rationale: record 0005.

| Pin | Signal | Boot | After release | Reset strap |
|---|---|---|---|---|
| 1 | `VDD` | — | — | — |
| 2 | `GND` | — | — | — |
| 3 | `flash_sclk`/`gpio0` | flash clock | GPIO bit 0 | — |
| 4 | `flash_cs_n`/`gpio1` | flash CS (low) | GPIO bit 1 | — |
| 5 | `flash_copi`/`gpio2` | flash data out | GPIO bit 2 | — |
| 6 | `flash_cipo`/`gpio3` | flash data in | GPIO bit 3 | — |
| 7 | `uart_rx` | console RX; UART-boot data | console RX | **low ⇒ UART boot** |
| 8 | `uart_tx` | (idle) | console TX | — |

## Memory map

| Region | Base | Size | Contents |
|---|---|---|---|
| RAM (RF + program + data) | `0x0000_0000` | 256 B | RF region `0x0000_0000`–`0x0000_003F`, then program/data; `RESET_PC = 0x0000_0000` |
| Peripherals | `0x4000_0000` | 4 KB window | UART `0x4000_0000`, timer `0x4000_0100`, GPIO `0x4000_0200` — registers in record 0004 |

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
