# 0007 — Compliance: riscv-arch-test 3.10.0 (pinned) via riscof, SAIL reference

- **Status**: proposed — flips to `RATIFIED` in this PR after the two
  independent reviews (engineering and market) required by the repo
  instructions.
- **Supersedes**: the README draft row "Compliance: passes the RISC-V
  architectural tests for the implemented base" in its version-free form.
- **Superseded by**: none.
- **Spec rows**: `spec/target-spec.md` row 10 (Compliance).

## Context

The draft says "the RISC-V architectural tests" without naming a suite or a
version, which cannot be verified. The pinned SERV tree defines the working
integration pattern (all read **2026-11-19**):

| Fact | Value | Source |
|---|---|---|
| Suite repo | https://github.com/riscv/riscv-arch-test (formerly `riscv-non-isa/riscv-arch-test`; the sibling SoC cites the old org path) | GitHub, 2026-11-19; sibling README @ `e1135913…` |
| Classic framework home | branch `old-framework-3.x`, riscof layout (`riscv-test-suite/`) | repo branch listing, 2026-11-19 |
| Suite version | **3.10.0** (CHANGELOG `[3.10.0] - 2024-11-04` is the top entry) | `CHANGELOG.md` @ `old-framework-3.x` |
| Pinned commit | **`9bceaf5c02fa1131625bc6228b834e9e884c5801`** (branch tip, 2026-02-19) | GitHub commits API, 2026-11-19 |
| `rv32i_m` suites present | `A`, `B`, `C`, `D`, `F`, `I`, `K`, `M`, `Zifencei`, `Zicond`, `Zimop`, `privilege`, `pmp`, … — **no `Zicsr` directory** | contents listing @ pin, 2026-11-19 |
| `rv32i_m/I` coverage at pin | 37 base-instruction tests + `fence` (no CSR-named tests) | `rv32i_m/I/src` listing @ pin, 2026-11-19 |
| `rv32i_m/Zifencei` | `Fencei.S` | listing @ pin, 2026-11-19 |
| `rv32i_m/privilege` | `ecall`/`ebreak`, envcfg illegal-access tests, misaligned-access traps (31 files) | listing @ pin, 2026-11-19 |
| Runner | riscof; SERV's CI runs `rv32i_m/I`, `M`, `C`, `Zifencei`, `privilege` against a SAIL-RISCV golden model (`ReferencePlugin=sail_cSim`) | olofk/serv `.github/workflows/ci.yml` + `verif/config.ini` @ pinned commit (record 0001) |
| Default-branch caveat | the repo's default branch is now `act4` (the successor "ACT" framework, different layout); the classic riscof layout lives on `old-framework-3.x` | branch listing + `act4` root listing, 2026-11-19 |
| Test-program build to copy | cocotb + Icarus harness and firmware/test-program build | 2AMLogic/sky130-riscv-soc @ **`e1135913b57ebf0cd57a7882772545fedb7291d0`** (`verification/`, `firmware/`), read 2026-11-19 |

One coverage gap must be stated rather than papered over: at the pinned
commit the classic suite has **no Zicsr (CSR-instruction) test directory** —
CSR coverage is not in `rv32i_m/I`, `Zifencei`, or `privilege`. The suite
also leans on S-mode/H-mode envcfg tests inside `privilege` that an
M-mode-only core does not implement.

## Decision

1. **Suite: riscv-arch-test, classic riscof framework**, pinned to
   **`9bceaf5c02fa1131625bc6228b834e9e884c5801`** (branch
   `old-framework-3.x`, suite version **3.10.0**). The pin is recorded in
   the verification flow when issue #2 lands the harness; the suite is
   fetched by script, not hand-copied.
2. **Suites run: `rv32i_m/I`, `rv32i_m/Zifencei`, `rv32i_m/privilege`** —
   exactly the pinned SERV CI set minus `M` and `C`, which this design does
   not implement (record 0001). The DUT plugin targets `rv32i_m` with
   `WITH_CSR=1`, `COMPRESSED=0`, `MDU=0`.
3. **Runner: riscof with SAIL-RISCV as the golden model**, mirroring SERV's
   `verif/config.ini` pattern (`ReferencePlugin=sail_cSim`); the SAIL model
   version is pinned beside the suite pin in the harness issue (#2), which
   owns the tool pins.
4. **CSR coverage is closed by cocotb tests, not by the suite.** The
   pinned suite has no Zicsr directory (fact above), so the CSR subset
   SERV implements is verified by dedicated cocotb testbenches written
   against the CSR list read from the pinned `serv_csr.v` — the RTL issue
   enumerates that list in its testbench, and this record's gap note is
   what stops anyone from calling the suite run "full Zicsr coverage".
5. **Privilege-suite subsetting, declared up front**: envcfg tests that
   require S-mode/H-mode are outside an M-mode-only core; the recorded run
   reports them as not-applicable with the reason, rather than silently
   skipping. `ecall`/`ebreak`/misaligned-trap tests apply and must pass
   (`WITH_CSR=1` gives machine traps; the fallback `WITH_CSR=0` build
   reduces the compliance target to `I` + `Zifencei`).
6. **Test-program build: copied from sky130-riscv-soc**, pinned
   **`e1135913b57ebf0cd57a7882772545fedb7291d0`** (2026-11-19): the cocotb
   + Icarus harness pattern from its `verification/` tree and the
   test-program build from its `firmware/` tree, adapted to this block's
   register map (record 0004) and 192 B program budget (record 0002).
7. **Evidence rule**: a compliance claim exists only as a recorded run in
   `verification/records/` (append-only) with the command path, suite pin,
   golden-model pin, and pass/fail per test group.

## Alternatives considered

- **Chasing the suite's default branch** (`act4`, the ACT framework).
  Rejected: it is a different, migrating framework; SERV's own CI runs the
  classic layout, so the classic branch is the pattern with a proven
  integration at our pinned core. Moving to ACT later supersedes this
  record.
- **riscv-tests (the older `riscv/riscv-tests` suite).** Rejected:
  different harness, not what the pinned ecosystem (SERV CI) integrates;
  can be revisited only by record.
- **Unpinned "latest" suite** (what SERV CI effectively does with
  `riscof arch-test --clone`). Rejected for *this* repo: an unpinned suite
  makes recorded results non-reproducible, which the evidence rules
  forbid.
- **M/C suites "for completeness".** Rejected: running tests for
  unimplemented extensions measures nothing; the config is fixed in
  record 0001.

## Consequences

- The verification issue (#2) inherits a fully named suite + pins; nothing
  there is left to taste.
- The compliance run is the ISA-level verification of the core row of
  `spec/target-spec.md`; passing it, plus the cocotb CSR tests, is what
  "passes the architectural tests" means everywhere in this repo.
- Suite moves (ACT migration) and model pins are versioned changes: new
  decision record, never a quiet re-pin.
