# flow/smoke

Requests that take the harness smoke DUT
([`verification/tests/smoke/smoke.v`](../../verification/tests/smoke/smoke.v),
an 8-bit free-running counter — **not design RTL**) through the six
implementation-flow verbs, driven end to end by one command:

```
make -C verification flow-smoke
```

The run is **toolchain evidence on a smoke DUT and nothing more**: it proves
this repo's pinned Yosys/OpenROAD/klt/PDK combination synthesizes, places,
routes, times, DRC-checks, LVS-checks and ERC-checks *a* design, and records
the evidence under `verification/records/flow-smoke/`. It is not cited in any
block manifest and claims nothing about the target spec (which awaits
ratification). No value here comes from that spec.

## The numbers are arbitrary

Every floorplan dimension and clock period in these requests is an arbitrary
value chosen so the toolchain runs, not a design target:

- `clock_period_ns: 20.0` on `clk` (par/sta, and synthesize's ABC delay
  target) — relaxed so the smoke DUT times clean; it says nothing about any
  real constraint.
- `par.json`'s explicit 60x60 um die with a 40x40 um core — sized above the
  ~28.8 um core the PDK's met5 strap pitch requires (see
  [`../README.md`](../README.md)), not from any area budget. An 8-flip-flop
  counter at a normal utilization would produce a core too small for the
  default PDN, so the floorplan is explicit instead.
- `seed: 1`, corner `tt_025C_1v80`, IO layers met3/met2 — defaults and
  first sensible choices, nothing measured.

## Requests

| File | Verb | Notes |
| --- | --- | --- |
| `synth.json` | `klt synthesize` | reads `verification/tests/smoke/smoke.v` directly (no copy); writes `flow/build/smoke/synth/` |
| `par.json` | `klt place-and-route` | to `target_stage: "route"`; carries [`../request-par.json`](../request-par.json)'s `power` block **unchanged** (the three default PDN straps); `portable_paths: true` so the committed envelope carries repo-relative paths |
| `sta.json` | `klt sta` | times the routed DEF (`geometry_source: "routed"`) at the arbitrary 20 ns period |
| `drc.json` | `klt drc` | curated sky130 deck on the merged routed GDS |
| `lvs.json` | `klt lvs` | `reference.form: "gate-level-verilog"` against P&R's as-built `smoke.v` (CTS buffers/tapcells/fillers included), `abstract_cells` for the standard cells, `def_net_names` to recover real net names, `power_connectivity.expected_nets` per [`../README.md`](../README.md) gate 2 |
| `erc.json` | `klt erc` | **spec file** (not a request document): sky130 stackup/vias, `VDD`/`VSS` as `kind: "supply"`, and the `nwell_tap` tie — gate 3. Run with `--top smoke --pdk sky130 --deck sky130` |

`../request-par.json` stays as the starter for the real design; these smoke
requests are the working, committed pattern for it.

Intermediate artifacts (netlist, DEF, GDS, logs) land under
`flow/build/smoke/`, which is gitignored scratch; the committed evidence is
the record's JSON envelopes, not the binaries.
