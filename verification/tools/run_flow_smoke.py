#!/usr/bin/env python3
"""Run the smoke DUT through the six implementation-flow verbs and record it.

    python3 -I verification/tools/run_flow_smoke.py

This script runs `scripts/setup-env.sh --check-flow` first -- the single
pin check (PDK revision, klt, the klayout engine it loads, Yosys, OpenROAD;
`scripts/setup-env.sh` is the one pin source, so no pin is re-derived here)
-- so both `make -C verification flow-smoke` (verification/Makefile) and a
direct `python3 -I verification/tools/run_flow_smoke.py` verify every pin
before any stage starts.

Stages, in order, each through the pinned `klt` and a committed request
document under `flow/smoke/` (see that directory's README -- the floorplan
and clock numbers are arbitrary smoke values, not design targets):

    synthesize  flow/smoke/synth.json   -> flow/build/smoke/synth/smoke_synth.v
    place-and-route flow/smoke/par.json -> flow/build/smoke/pnr/{smoke.def,smoke.gds,smoke.v}
    sta         flow/smoke/sta.json     (routed DEF)
    drc         flow/smoke/drc.json     (merged GDS)
    lvs         flow/smoke/lvs.json     (GDS vs as-built gate-level Verilog)
    erc         flow/smoke/erc.json     (spec; supply islands + nwell tap)

Each verb's JSON envelope is written verbatim into an append-only record
under verification/records/flow-smoke/<UTC-timestamp>-<sha>/ together with a
provenance.json that passes verification/tools/lint_records.py (pdk_revision
and tool_versions are probed from the installed PDK and the tools that
actually ran -- never copied from the pins). Probes run before the record
directory is created, so a failed probe writes nothing (the smoke target's
atomic-write discipline).

The run FAILS (exit 1) unless every gate below passes, but the record is
written either way -- a failing envelope is evidence, and a gate that cannot
pass because of a klayout-tools gap stays failing with the envelope recorded
(friction protocol; never weaken or skip a gate):

    synthesize       structural.unexpected_latches == 0, structural.comb_loops
                     == 0, structural.multi_driven == 0
    place-and-route  power.pdn == true, power.tapcell_master non-empty,
                     power.placed.status == "complete" (the placed-power
                     audit's vocabulary; it never emits "ok"),
                     power.placed.tapcells > 0
    sta              timing_status == "constrained", worst_slack_ns >= 0,
                     worst_hold_slack_ns >= 0 when non-null
    drc              status == "clean", violation_count == 0
    lvs              status == "match", power_connectivity.status == "match",
                     power_connectivity.unchecked_expected_pins empty (a
                     declared power expectation that resolved zero rows is a
                     failure, not a pass; an absent key fails too -- the
                     pinned klt always emits the field)
    erc              erc_status == "clean", a nets[] row named "VDD" and one
                     named "VSS" each with matched_islands == 1 (output rows
                     key on name and do not echo kind), the tie work id
                     'erc.missing_tie:["nwell_tap"]' in erc_coverage.checked
                     and not in erc_coverage.skipped, zero findings whose
                     rule is erc.missing_tie / erc.supply_short /
                     erc.unconnected_net

The run log also pairs the synthesize envelope's netlist_sha256 with the
Yosys build string and a banner-normalised netlist hash: klt's hash covers
the Yosys banner verbatim, and that banner names the compiler that built
Yosys, so two differently-built Yosys at the same PIN_YOSYS/PIN_YOSYS_SHA
hash differently for identical netlist content (issue #32).

A stage whose subprocess dies without a JSON envelope is recorded as an
error artifact and every stage downstream of it is skipped (recorded as
errors too) -- the record always tells the whole story.

Stdlib only; no EDA tool is re-implemented here (every check above reads a
klt envelope).
"""
from __future__ import annotations

import datetime
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

VERBS = ("synthesize", "place-and-route", "sta", "drc", "lvs", "erc")
#: files each stage needs on disk before it may run (repo-relative)
STAGE_INPUTS = {
    "place-and-route": ("flow/build/smoke/synth/smoke_synth.v",),
    "sta": ("flow/build/smoke/pnr/smoke.def",),
    "drc": ("flow/build/smoke/pnr/smoke.gds",),
    "lvs": ("flow/build/smoke/pnr/smoke.gds", "flow/build/smoke/pnr/smoke.v"),
    "erc": ("flow/build/smoke/pnr/smoke.gds",),
}


def pin_pdk_variant(setup_env: Path) -> str:
    """The PDK variant, read from scripts/setup-env.sh (the single pin source)."""
    m = re.search(r'^PIN_PDK_VARIANT="([^"]+)"', setup_env.read_text(), re.M)
    if not m:
        raise RuntimeError(f"PIN_PDK_VARIANT not found in {setup_env}")
    return m.group(1)


PDK_VARIANT = pin_pdk_variant(
    Path(__file__).resolve().parent.parent.parent / "scripts" / "setup-env.sh")
SCRATCH = "flow/build/smoke"
RECORD_KIND = "flow-smoke"

ERC_SUPPLY_NETS = ("VDD", "VSS")
ERC_TIE_ID = 'erc.missing_tie:["nwell_tap"]'
ERC_GATED_RULES = ("erc.missing_tie", "erc.supply_short", "erc.unconnected_net")


# --------------------------------------------------------------------------
# gate grading -- pure, exercised directly by tests/test_run_flow_smoke.py
# --------------------------------------------------------------------------
def _num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def grade_envelope(verb: str, env: dict) -> list[str]:
    """Gate failures (empty list == pass) for one verb's envelope."""
    f: list[str] = []
    bad = lambda g, why: f.append(f"{verb}: gate {g}: {why}")  # noqa: E731
    if verb == "synthesize":
        st = env.get("structural") or {}
        for key in ("unexpected_latches", "comb_loops", "multi_driven"):
            if st.get(key) != 0:
                bad(f"structural.{key}", f"got {st.get(key)!r}, want 0")
    elif verb == "place-and-route":
        p = env.get("power") or {}
        if p.get("pdn") is not True:
            bad("power.pdn", f"got {p.get('pdn')!r}, want true")
        if not p.get("tapcell_master"):
            bad("power.tapcell_master", f"got {p.get('tapcell_master')!r}, want a named master")
        placed = p.get("placed") or {}
        if placed.get("status") != "complete":
            bad("power.placed.status",
                f"got {placed.get('status')!r}, want \"complete\""
                + (f" (missing: {placed.get('missing')})" if placed.get("missing") else ""))
        if not _num(placed.get("tapcells")) or placed.get("tapcells") <= 0:
            bad("power.placed.tapcells", f"got {placed.get('tapcells')!r}, want > 0")
    elif verb == "sta":
        if env.get("timing_status") != "constrained":
            bad("timing_status", f"got {env.get('timing_status')!r}, want \"constrained\"")
        ws = env.get("worst_slack_ns")
        if not _num(ws) or ws < 0:
            bad("worst_slack_ns", f"got {ws!r}, want >= 0")
        wh = env.get("worst_hold_slack_ns")
        if wh is not None and (not _num(wh) or wh < 0):
            bad("worst_hold_slack_ns", f"got {wh!r}, want >= 0 when non-null")
    elif verb == "drc":
        if env.get("status") != "clean":
            bad("status", f"got {env.get('status')!r}, want \"clean\"")
        if env.get("violation_count") != 0:
            bad("violation_count", f"got {env.get('violation_count')!r}, want 0")
    elif verb == "lvs":
        if env.get("status") != "match":
            bad("status", f"got {env.get('status')!r}, want \"match\"")
        pc = env.get("power_connectivity") or {}
        if pc.get("status") != "match":
            bad("power_connectivity.status",
                f"got {pc.get('status')!r}, want \"match\""
                + (f" (reason: {pc.get('reason')})" if pc.get("reason") else ""))
        unchecked = pc.get("unchecked_expected_pins")
        if not isinstance(unchecked, list):
            bad("power_connectivity.unchecked_expected_pins",
                f"got {unchecked!r}, want a list of pins -- without it the gate "
                "cannot tell checked from unchecked (the pinned klt always emits it)")
        elif unchecked:
            bad("power_connectivity.unchecked_expected_pins",
                f"{len(unchecked)} expected pin(s) went unchecked (declared in "
                "expected_nets but resolved zero rows -- the check could not "
                "run, which is not a pass): " + ", ".join(str(x) for x in unchecked))
    elif verb == "erc":
        if env.get("erc_status") != "clean":
            bad("erc_status", f"got {env.get('erc_status')!r}, want \"clean\"")
        rows = {n.get("name"): n for n in env.get("nets") or [] if isinstance(n, dict)}
        for net in ERC_SUPPLY_NETS:
            row = rows.get(net)
            if row is None:
                bad("erc.nets[]", f"no row named {net!r} (rows key on name, not kind)")
            elif row.get("matched_islands") != 1:
                bad(f"erc.nets[{net}].matched_islands",
                    f"got {row.get('matched_islands')!r}, want 1")
        cov = env.get("erc_coverage") or {}
        checked = cov.get("checked") or []
        skipped = cov.get("skipped") or []
        if ERC_TIE_ID not in checked:
            bad("erc_coverage.checked", f"{ERC_TIE_ID} absent (tie check did not run)")
        if any(isinstance(s, dict) and s.get("id") == ERC_TIE_ID for s in skipped):
            bad("erc_coverage.skipped", f"{ERC_TIE_ID} skipped (degenerate tie declaration)")
        gated = [x for x in env.get("erc_findings") or []
                 if isinstance(x, dict) and x.get("rule") in ERC_GATED_RULES]
        if gated:
            bad("erc_findings", f"{len(gated)} finding(s) in {ERC_GATED_RULES}: "
                                + "; ".join(str(x.get('rule')) for x in gated[:3]))
        if env.get("erc_finding_count") not in (0, None):
            bad("erc_finding_count", f"got {env.get('erc_finding_count')!r}, want 0")
    return f


#: Yosys writes its full version+build banner as the netlist's first line;
#: the build string names the compiler that built Yosys, so it is the only
#: netlist text that varies between two Yosys builds at the same pinned
#: version (issue #32)
YOSYS_BANNER = re.compile(rb"^/\* Generated by Yosys .*\*/\n")


def normalised_netlist_sha256(data: bytes) -> str:
    """sha256 over the netlist with a *leading* Yosys banner line removed.

    klt's netlist_sha256 covers the file verbatim, banner included, so two
    hosts with differently-built Yosys at the same PIN_YOSYS/PIN_YOSYS_SHA
    record different hashes for byte-identical netlist content (issue #32:
    the GNU- and Clang-built 0.67+post differ only in that line). With no
    leading banner the hash covers the file verbatim."""
    return hashlib.sha256(YOSYS_BANNER.sub(b"", data, count=1)).hexdigest()


def netlist_hash_note(envelope: dict, root: Path, yosys_build: str) -> str:
    """Log line pairing klt's netlist_sha256 with the Yosys build string and
    the banner-normalised hash, so two records can be compared without
    guessing whether a hash difference is a design change or a Yosys build
    change (issue #32)."""
    rel = (envelope.get("netlist_path") or {}).get("path")
    raw = envelope.get("netlist_sha256")
    if not rel or not raw:
        return "   netlist hashes: not recorded (envelope lacks netlist_path/netlist_sha256)"
    try:
        data = (root / rel).read_bytes()
    except OSError as e:
        return f"   netlist hashes: not recorded (cannot read {rel}: {e})"
    return (f"   netlist hashes: netlist_sha256={raw}"
            f" netlist_sha256_banner_normalised={normalised_netlist_sha256(data)}"
            f" (yosys build: {yosys_build})")


def grade_result(result: dict[str, dict]) -> list[str]:
    """Grade every verb; a stage that produced no envelope fails all its gates."""
    f: list[str] = []
    for verb in VERBS:
        env = result.get(verb)
        if not isinstance(env, dict) or "_error" in env:
            f.append(f"{verb}: stage did not produce an envelope: "
                     f"{(env or {}).get('_error', 'missing')}")
            continue
        f += grade_envelope(verb, env)
    return f


# --------------------------------------------------------------------------
# runner
# --------------------------------------------------------------------------
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def probe(root: Path, klt_cmd: list[str]) -> dict[str, Any]:
    """Probe everything provenance.json needs BEFORE creating the record.

    Pins are not checked here -- main() runs `scripts/setup-env.sh
    --check-flow`, the single pin check, before anything else. This collects
    only the live values the record commits to: the commit, the installed
    PDK's open_pdks revision, and the tool versions that actually ran."""
    sha = run(["git", "-C", str(root), "rev-parse", "HEAD"])
    if sha.returncode != 0 or not sha.stdout.strip():
        raise RuntimeError(f"cannot probe git HEAD: {sha.stderr.strip() or sha.returncode}")
    pdk_root = Path(os.environ.get("PDK_ROOT") or str(Path.home() / ".ciel"))
    sources = pdk_root / PDK_VARIANT / "SOURCES"
    try:
        rev = ""
        for line in sources.read_text().splitlines():
            if line.startswith("open_pdks"):
                parts = line.split()
                rev = parts[1] if len(parts) > 1 else ""
                break
        if not rev:
            raise ValueError("no open_pdks line")
    except (OSError, ValueError) as e:
        raise RuntimeError(f"cannot probe pdk revision from {sources}: {e}") from e
    tools: dict[str, str] = {}
    kver = run(klt_cmd + ["--version"])
    if kver.returncode != 0 or not kver.stdout.strip():
        raise RuntimeError(f"klt version probe failed: "
                           f"{kver.stdout.strip() or kver.stderr.strip()}")
    tools["klt"] = kver.stdout.strip().splitlines()[0]
    for name, cmd in (("yosys", ["yosys", "-V"]),
                      ("openroad", ["openroad", "-version"])):
        r = run(cmd)
        first = (r.stdout + r.stderr).strip().splitlines()[0] if (r.stdout + r.stderr).strip() else ""
        if r.returncode != 0 or not first:
            raise RuntimeError(f"{name} probe failed: got '{first}'")
        tools[name] = first
    return {"commit": sha.stdout.strip(), "pdk_revision": rev, "tools": tools,
            "pdk_variant": PDK_VARIANT}


def stage_argv(klt_cmd: list[str], verb: str) -> list[str]:
    # paths are repo-relative: cwd is the repo root, and klt erc echoes the
    # spec path verbatim into its envelope (an absolute one would leak a
    # home path into the committed record)
    if verb == "synthesize":
        return klt_cmd + ["synthesize", "--format", "json", "--pdk", PDK_VARIANT,
                          "flow/smoke/synth.json"]
    if verb == "place-and-route":
        return klt_cmd + ["place-and-route", "--format", "json", "--pdk", PDK_VARIANT,
                          "flow/smoke/par.json"]
    if verb == "sta":
        return klt_cmd + ["sta", "--format", "json", "--pdk", PDK_VARIANT,
                          "flow/smoke/sta.json"]
    if verb == "drc":
        return klt_cmd + ["drc", "--format", "json", "flow/smoke/drc.json"]
    if verb == "lvs":
        return klt_cmd + ["lvs", "--format", "json", "flow/smoke/lvs.json"]
    if verb == "erc":
        return klt_cmd + ["erc", "--format", "json", "--top", "smoke", "--pdk", "sky130",
                          "--deck", "sky130", f"{SCRATCH}/pnr/smoke.gds",
                          "flow/smoke/erc.json"]
    raise ValueError(verb)


def display_cmd(argv: list[str], root: Path) -> list[str]:
    """argv with repo-internal absolute paths shown repo-relative, so the
    committed run log carries no host/home path (env-provenance scan)."""
    out = []
    for a in argv:
        p = Path(a)
        if p.is_absolute():
            try:
                a = str(p.relative_to(root))
            except ValueError:
                pass
        out.append(a)
    return out


def main(argv: list[str]) -> int:
    root = repo_root()
    env = dict(os.environ)
    env.setdefault("PDK_ROOT", str(Path.home() / ".ciel"))

    # the one pin check: scripts/setup-env.sh is the single pin source, and
    # its --check-flow output is forwarded verbatim. Nothing below runs (no
    # --klt-bin, no scratch cleanup, no record) on any pin mismatch.
    cf = run(["bash", str(root / "scripts" / "setup-env.sh"), "--check-flow"],
             env=env)
    sys.stdout.write(cf.stdout)
    sys.stderr.write(cf.stderr)
    if cf.returncode != 0:
        print("flow pins do not match (scripts/setup-env.sh --check-flow); "
              "nothing recorded", file=sys.stderr)
        return 1

    kb = run(["bash", str(root / "scripts" / "setup-env.sh"), "--klt-bin"])
    if kb.returncode != 0 or not kb.stdout.strip():
        print(f"cannot resolve the pinned klt: {kb.stderr.strip()}", file=sys.stderr)
        return 1
    klt_cmd = shlex.split(kb.stdout.strip())

    try:
        prov = probe(root, klt_cmd)
    except RuntimeError as e:
        print(f"probe failed, nothing recorded: {e}", file=sys.stderr)
        print("(scripts/setup-env.sh --fetch-pdk provisions a cold host)",
              file=sys.stderr)
        return 1

    # fresh scratch: klt claims its output dirs exclusively, and this target
    # is a from-scratch run by contract (flow/build/ is gitignored)
    shutil.rmtree(root / SCRATCH, ignore_errors=True)

    log: list[str] = [f"klt: {' '.join(display_cmd(klt_cmd, root))}",
                      f"commit: {prov['commit']}",
                      f"pdk: {prov['pdk_variant']} open_pdks {prov['pdk_revision']}"]
    result: dict[str, dict] = {}
    envelopes: dict[str, dict] = {}
    hard_failed = False

    for verb in VERBS:
        if hard_failed:
            result[verb] = {"_error": f"skipped: upstream stage failed"}
            log.append(f"== {verb}: SKIPPED (upstream failure)")
            continue
        missing = [str(rel) for rel in STAGE_INPUTS.get(verb, ()) if not (root / rel).is_file()]
        if missing:
            result[verb] = {"_error": f"skipped: missing stage input(s): {', '.join(missing)}"}
            log.append(f"== {verb}: SKIPPED (missing inputs: {', '.join(missing)})")
            hard_failed = True
            continue
        argv = stage_argv(klt_cmd, verb)
        log.append(f"== {verb}: {' '.join(display_cmd(argv, root))}")
        r = run(argv, env=env, cwd=str(root))
        log.append(f"   exit {r.returncode}")
        for line in (r.stderr.strip().splitlines()[-8:] if r.stderr.strip() else []):
            log.append(f"   | {line}")
        try:
            envelope = json.loads(r.stdout)
            if not isinstance(envelope, dict):
                raise ValueError("top level is not an object")
        except ValueError as e:
            tail = (r.stderr.strip().splitlines() or ["<no stderr>"])[-5:]
            result[verb] = {"_error": f"no JSON envelope (exit {r.returncode}): "
                                      f"{'; '.join(tail)}"}
            log.append(f"   NO ENVELOPE ({e}); last stderr:")
            log += [f"   | {x}" for x in tail]
            hard_failed = True
            continue
        envelopes[verb] = envelope
        result[verb] = envelope
        fails = grade_envelope(verb, envelope)
        log.append(f"   gates: {'PASS' if not fails else 'FAIL ' + '; '.join(fails)}")
        if verb == "synthesize":
            log.append(netlist_hash_note(envelope, root, prov["tools"]["yosys"]))

    # klayout version: probed from the klt that ran, as its own envelopes
    # report it (never copied from a pin)
    for verb in VERBS:
        kv = ((envelopes.get(verb) or {}).get("provenance") or {}).get("klayout_version")
        if kv:
            prov["tools"]["klayout"] = f"klayout {kv}"
            break

    failures = grade_result(result)

    recs = root / "verification" / "records" / RECORD_KIND
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    while (recs / f"{ts}-{prov['commit']}").exists():
        time.sleep(1)
        ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    rec = recs / f"{ts}-{prov['commit']}"
    rec.mkdir(parents=True)
    for verb in VERBS:
        payload = result[verb]
        if verb in envelopes:
            (rec / f"{verb}.json").write_text(
                json.dumps(envelopes[verb], indent=2, sort_keys=True) + "\n")
        else:
            (rec / f"{verb}.error.json").write_text(
                json.dumps(payload, indent=2, sort_keys=True) + "\n")
    (rec / "flow-smoke.log.txt").write_text("\n".join(log) + "\n")
    (rec / "provenance.json").write_text(json.dumps({
        "commit": prov["commit"],
        "pdk_revision": prov["pdk_revision"],
        "tool_versions": prov["tools"],
        "command": "make -C verification flow-smoke",
    }, indent=2) + "\n")

    print(f"record: {rec.relative_to(root)}")
    for f in failures:
        print(f"GATE FAIL {f}", file=sys.stderr)
    if failures:
        print(f"flow-smoke: FAIL ({len(failures)} gate failure(s)); "
              f"envelopes recorded in {rec.relative_to(root)}", file=sys.stderr)
        return 1
    print("flow-smoke: PASS (all gates)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
