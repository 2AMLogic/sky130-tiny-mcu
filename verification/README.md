# verification

The cocotb + Icarus harness this repo's claims are checked with, and the
append-only evidence trail they are recorded in. Verification is the product:
no claim without a testbench committed here with a cold-start command a third
party can run.

| Path | Holds |
| --- | --- |
| `Makefile`, `cocotb.mk` | the single runner entry point (cocotb + Icarus Verilog); `smoke` for the harness, `flow-smoke` for the implementation flow — the two targets until design RTL exists |
| `tests/smoke/` | the harness smoke test (`make smoke`): a trivial counter DUT and its cocotb module, self-contained, **not** design RTL |
| `tools/lint_records.py` | linter for `records/` (stdlib only) |
| `tools/run_flow_smoke.py` | the implementation-flow runner (`make flow-smoke`): drives the six `klt` verbs request-by-request, gates on their JSON envelopes, writes the append-only `records/flow-smoke/` record |
| `tools/tests/` | good and bad record fixtures for the linter, the linter's fixture test, and the flow-smoke gate tests (`test_run_flow_smoke.py`, no PDK or EDA tools needed) |
| `records/` | append-only evidence; layout in [`records/README.md`](records/README.md) |

## Cold start

Needs `iverilog` and `cocotb` at the versions pinned in
[`../scripts/setup-env.sh`](../scripts/setup-env.sh), the one pin source;
`--check` verifies the environment against them and fails, never skips, on a
mismatch.

```
python3 -m venv .venv && .venv/bin/pip install \
    "cocotb==$(sed -n 's/^PIN_COCOTB="\([^"]*\)".*/\1/p' scripts/setup-env.sh)"
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

## Cold start, implementation flow (`make flow-smoke`)

The flow target additionally needs the flow pins — the sky130A PDK at the
pinned open_pdks revision, `klt` at the pinned klayout-tools release (install
it into the same venv: `.venv/bin/pip install
"klayout-tools==$(sed -n 's/^PIN_KLT="\([^"]*\)".*/\1/p' scripts/setup-env.sh)"`,
or let `setup-env.sh` resolve it through `uvx`), Yosys and OpenROAD. Two more
check modes cover them:

| Command | What it verifies |
| --- | --- |
| `scripts/setup-env.sh --check` | the simulation pins only (cocotb, iverilog) — exactly what hosted CI runs on runners with no PDK/klt/Yosys/OpenROAD |
| `scripts/setup-env.sh --check-flow` | the simulation pins **plus** the PDK revision, klt version, every `klt_required_commands` entry in `klt --help`, Yosys and OpenROAD; fails, never skips, on any mismatch or absence |
| `scripts/setup-env.sh --fetch-pdk` | fetches sky130A at the pinned open_pdks revision into `${PDK_ROOT:-~/.ciel}` via ciel (through `uvx`), then runs `--check-flow` |

```
. .venv/bin/activate
scripts/setup-env.sh --fetch-pdk     # cold host: PDK first
make -C verification flow-smoke      # runs --check-flow, then the flow
```

`make flow-smoke` runs synthesize, place-and-route, STA, DRC, LVS and ERC on
the smoke DUT through the request documents in [`../flow/smoke/`](../flow/smoke/)
and writes `records/flow-smoke/<UTC-timestamp>-<sha>/` with the six JSON
envelopes, the run log and a `provenance.json` whose `pdk_revision` and
`tool_versions` are probed from the installed PDK and the tools that ran.
The target fails unless every gate passes
([`../flow/README.md`](../flow/README.md) — the three power-delivery gates
included) but records the envelopes either way: a failing envelope is
evidence. This run is toolchain evidence on a smoke DUT, not design RTL; it
is not cited in any block manifest.

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
- a `flow-smoke` target and `tools/run_flow_smoke.py` (issue #21), written
  here, driving `klt` request documents under `../flow/smoke/` — the
  sibling's flow requests (at `b201244`) are the pattern, but the requests,
  the gates and the runner are this repo's own
- a single sim target (`smoke`) plus the flow target -- no
  xbar/periph/boot/SoC/gate targets, no `tests/lib` shared bench core, no
  models
- `pdk_revision` in smoke provenance is the explicit note
  `"n/a, no PDK used (RTL simulation only)"`; the flow-smoke provenance
  probes the real open_pdks revision from the installed PDK (the flow pins
  live in `setup-env.sh` too, verified by `--check-flow`)
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
| `python3 -I verification/tools/tests/test_run_flow_smoke.py` | the flow-smoke gate grading against its passing/negative envelope fixtures (no PDK or EDA tools needed) |
| `scripts/tests/test-setup-env.sh` | the two check modes of `setup-env.sh`, on a hermetic stub toolchain |

PDK-heavy legs (synthesis, P&R, DRC, LVS, ERC) stay out of hosted CI — the
runner has no PDK, klt, Yosys or OpenROAD, and bare `setup-env.sh --check`
must keep passing without them. The flow runs locally via
`make -C verification flow-smoke` and records under `records/flow-smoke/`;
CI's records-lint step covers that tree too, so a committed flow-smoke
record must pass the linter there.
