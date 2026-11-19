# flow

Synthesis and place-and-route recipes (Yosys, OpenROAD), driven through klt.

## Structural power delivery (T1 item 11)

**Every `klt place-and-route` request in this directory carries a `power`
block, and every digital claim built on one is gated on three reads, not
one.** Without `request.power`, `klt place-and-route` still reaches
`target_stage: "route"` and reports `status: "ok"` having run no `tapcell`,
no `global_connect`, no `pdngen` and no filler placement — the routed DEF
has no `SPECIALNETS` section at all, and gate-level LVS still reports
`match`, because a signal-only compare has nothing to say about power. That
is the exact shape `sky130-fpga#41` and `sky130-usb2-phy#59` shipped with.

**`power.row_rail.emitted: true` in a response is not evidence of a PDN
either.** It is a `sky130_fd_sc_hd`-only routing-obstruction fallback
(klayout-tools issue #1442): a real, drawn row-rail shape that keeps the
router from treating a standard cell's own `VPWR`/`VGND` rail as open space
even when `request.power` was omitted entirely. It draws no strap grid, runs
no `tapcell`, and inserts no filler — `emitted: true` only means the
fallback fired, never that a PDN exists.

The three gates, and where each is read:

1. **`power.pdn: true`** in the P&R response, with a named tapcell master.
2. **`power_connectivity.status: "match"`** in a `klt lvs` response — which
   requires `reference.form: "gate-level-verilog"`, the only reference form
   for which `klt lvs` runs the power/ground half of the compare at all.
   Gate on **both** `status` and `power_connectivity.status`; the exit code
   reflects the signal verdict only.
3. **A `klt erc` supply read** declaring `power_net`/`ground_net` as
   `"kind": "supply"` over every strap layer, reporting one electrical
   island per supply and zero `missing_tie`.

`request-par.json` in this directory is a starter request carrying this
PDK's default PDN strap geometry in its `power` block (`power_net`/
`ground_net` plus `straps[]`, layers listed bottom-to-top) — gate 1
above. Fill in the `<!-- FILL: ... -->` markers (netlist path, top-level
module, floorplan utilization, IO layers, clock constraints) once synthesis
is wired up; the `power` block itself needs no per-block edits. Gates 2
and 3 still need their own requests — a `klt lvs` request with
`reference.form: "gate-level-verilog"` and `options.power_connectivity`,
and a `klt erc` supply spec — once there is a routed layout to check.
