# spec

Proposed specification and decision records for the sky130-tiny-mcu block.

- **[target-spec.md](target-spec.md)** — the parameter table (target /
  fallback / stretch / verification per row), pin mux, memory map, and the
  no-relaxation and evidence rules.
- **[decisions/](decisions/)** — one decision record per parameter group:

  | Record | Group |
  |---|---|
  | [0001](decisions/0001-core.md) | Core (SERV by pinned reference, ISA config, interrupts, supply) |
  | [0002](decisions/0002-memory.md) | Memory (256 B single-port standard-cell RAM) |
  | [0003](decisions/0003-program-storage.md) | Program storage (SPI-flash copy-boot; mask ROM rejected) |
  | [0004](decisions/0004-peripherals.md) | Peripherals (one timer, one UART, the absent-list, register map) |
  | [0005](decisions/0005-pins.md) | Pins (8-pin assignment, internal clock, GPIO mux) |
  | [0006](decisions/0006-size-claim.md) | Size claim (what is measured, comparison set, command path) |
  | [0007](decisions/0007-compliance.md) | Compliance (riscv-arch-test 3.10.0 pinned, riscof + SAIL) |

Records carry a `Status:` line: `proposed` until this spec's PR merges —
ratification is that merge, after two independent reviews (engineering and
market) by sessions that did not author the PR; the status lines flip to
`RATIFIED` in the PR itself. Changes to any ratified row go through a new
decision record. Agents do not relax a row to make a result pass.
