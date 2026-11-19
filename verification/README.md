# verification

The cocotb + Icarus harness this repo's claims are checked with, and the
append-only evidence trail they are recorded in. Verification is the product:
no claim without a testbench committed here with a cold-start command a third
party can run.

| Path | Holds |
| --- | --- |
| `Makefile`, `cocotb.mk` | the single runner entry point (cocotb + Icarus Verilog); `smoke` is the one target until design RTL exists |
| `tests/smoke/` | the harness smoke test (`make smoke`): a trivial counter DUT and its cocotb module, self-contained, **not** design RTL |
| `tools/lint_records.py` | linter for `records/` (stdlib only) |
| `tools/tests/` | good and bad record fixtures for the linter, and the linter's fixture test |
| `records/` | append-only evidence; layout in [`records/README.md`](records/README.md) |

## Cold start

Needs `iverilog` 13.0 and `cocotb` 2.0.1 (pins in
[`../scripts/setup-env.sh`](../scripts/setup-env.sh), the one pin source;
`--check` verifies the environment against them and fails, never skips, on a
mismatch).

```
python3 -m venv .venv && .venv/bin/pip install cocotb==2.0.1
. .venv/bin/activate
scripts/setup-env.sh --check
make -C verification smoke    # fails if cocotb or iverilog is missing
```

`make smoke` runs the cocotb test on the counter DUT and writes
`records/smoke/<UTC-timestamp>-<sha>/` with `provenance.json`, the simulator
log and `results.xml`. A re-run adds a new record; it never edits an existing
one.

Adding a testbench: put it in `tests/<name>/` and add a target to the
`Makefile` that starts with the `$(CHECK_COCOTB)` / `$(CHECK_IVERILOG)` guards
and sets `TESTDIR`, `TOPLEVEL`, `MODULE`, `VERILOG_SOURCES` and `SIM_BUILD`
for [`cocotb.mk`](cocotb.mk), as `smoke` does.

## What is generic, what is specific to this block

Copied by pattern from the sibling
[`2AMLogic/sky130-riscv-soc`](https://github.com/2AMLogic/sky130-riscv-soc) at
`7ab764ccf95170d91f0286152f23fd2427375e2c` (2026-11-18), then cut down; the
patterns, not the files, were taken, so no SoC/peripheral/core material was
vendored:

- the runner shape: a `Makefile` of guarded targets delegating to
  `cocotb.mk` (Icarus via cocotb's `Makefile.sim`, `SIM_BUILD` per target,
  results file under it), with `CHECK_COCOTB` as a fail-not-skip guard
- `scripts/setup-env.sh` as the single pin source, read by CI with the same
  `sed` extraction of `PIN_*`
- `tools/lint_records.py` and its good/bad fixture test, verbatim
- the `records/` layout and its `README.md` explanation
- the CI shape: same triggers (`pull_request`, `merge_group`, `push: main`),
  no path filters, per-entry merge-queue concurrency, iverilog built from
  source at the pin + venv cocotb at the pin, and the environment verified
  against both pins before anything runs

Specific to this block:

- the smoke DUT and test themselves (`tests/smoke/`), written here; they
  claim nothing about the design
- a single target (`smoke`) -- no xbar/periph/boot/SoC/gate targets, no
  `tests/lib` shared bench core, no models
- `pdk_revision` in smoke provenance is the explicit note
  `"n/a, no PDK used (RTL simulation only)"`; PDK, synthesis and P&R tool
  pins enter `setup-env.sh` only when a flow first uses them
- the CI job (`smoke`) adds a fail-not-skip negative step: the harness must
  fail when cocotb is missing

## What CI runs

`.github/workflows/ci.yml`, one `smoke` job on pull requests, merge-group
queue entries and pushes to `main`:

| Step | What it covers |
| --- | --- |
| iverilog built from source at the pin | Icarus at `PIN_IVERILOG` from `../scripts/setup-env.sh` (tag `v<major>_<minor>`); the runner image's apt package is older than the pin |
| venv + `pip install cocotb==PIN_COCOTB` | cocotb at the version pinned in `../scripts/setup-env.sh`, read from it |
| `scripts/setup-env.sh --check` | the whole environment verified against both pins before anything runs; fails, never skips, on a mismatch |
| without cocotb, `make smoke` must fail | the fail-not-skip guard, exercised against the runner's bare `python3` |
| `make -C verification smoke` | the smoke test, on a clean checkout, writing a record |
| `python3 -I verification/tools/lint_records.py` | the records tree (including the record the run just wrote) |
| `python3 -I verification/tools/tests/test_lint_records.py` | the linter against its good/bad fixtures |

PDK-heavy legs (synthesis, P&R, DRC, LVS) do not exist yet; when added they
run locally and record under `records/`, and CI says nothing about them.
