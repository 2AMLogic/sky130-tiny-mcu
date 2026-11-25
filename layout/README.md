# layout

GDS and DRC/LVS reports. Empty until there is something to lay out — but the
toolchain that will check it is already pinned and exercised:

## Toolchain pin (`toolchain.json`)

[`toolchain.json`](toolchain.json) states the klt pin (`klayout-tools==0.9.2`,
its `v0.9.2` commit restated in `klt_last_verified_commit`), the `klayout`
package floor (`klayout_package_min`) and its exact pin
(`klayout_package_pin` — the engine that klt release was tested against; klt
declares only the floor, so the exact version is pinned here and in
`scripts/setup-env.sh`), and every `klt` verb this repo's runners invoke in
`klt_required_commands` (`synthesize`, `place-and-route`, `sta`, `drc`, `lvs`,
`erc`). `scripts/setup-env.sh --check-flow` verifies all of it — the resolved
klt's version, the klayout engine it loads, and each required command in its
`--help` — before any flow runner starts, and fails, never skips, on a
mismatch. Its `_comment` is append-only: each later pin bump adds a
paragraph, never edits one.

## Layout checks today

The only layout-producing flow today is the smoke flow run,
`make -C verification flow-smoke` (see [`../flow/smoke/`](../flow/smoke/) —
a smoke DUT, not design RTL): it places and routes that DUT, then runs the
layout checks against the routed GDS — curated sky130 DRC (`drc.json`),
gate-level LVS with power connectivity (`lvs.json`) and the ERC supply/tie
read (`erc.json`) — recording every JSON envelope under
`verification/records/flow-smoke/`. Those records are toolchain evidence on
a smoke DUT and are not cited in any block manifest.

No real design layout exists yet; when one does, its DRC/LVS evidence lands
here and under `verification/records/` the same way.
