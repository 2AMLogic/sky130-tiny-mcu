#!/usr/bin/env python3
"""Fixture tests for run_flow_smoke's envelope grading (issue #21).

Exercises grade_envelope/grade_result directly, with the six-verb envelope
shapes the pinned klt (klayout-tools 0.9.2) emits -- no PDK, klt, Yosys or
OpenROAD needed. The negative cases cover the misgradings called out in the
issue's review: a partial placed-power audit, an absent supply row in erc
nets[] (output rows key on name and never echo kind, so a kind filter can
select zero rows and silently pass), and a skipped tie check.
"""
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from run_flow_smoke import (  # noqa: E402
    VERBS,
    engine_pin_error,
    grade_envelope,
    grade_result,
    netlist_hash_note,
    normalised_netlist_sha256,
    pins,
    repo_root,
)


def synth_env(**structural) -> dict:
    base = {"unexpected_latches": 0, "comb_loops": 0, "multi_driven": 0}
    base.update(structural)
    return {"schema_version": 1, "hdl_toplevel": "smoke", "structural": base}


def par_env(power: dict | None = None) -> dict:
    p = {
        "pdn": True,
        "global_connect": True,
        "power_net": "VDD",
        "ground_net": "VSS",
        "tapcell_master": "sky130_fd_sc_hd__tapvpwrvgnd_1",
        "filler_masters": ["sky130_fd_sc_hd__fill_1"],
        "placed": {
            "evidence": "def",
            "status": "complete",
            "missing": [],
            "components": 40,
            "tapcells": 24,
            "endcaps": 8,
            "fillers": 4,
            "special_nets": [
                {"name": "VDD", "use": "POWER", "followpin_segments": 8,
                 "stripe_segments": 4, "other_segments": 0,
                 "stripe_layers": ["met4", "met5"], "vias": 20},
                {"name": "VSS", "use": "GROUND", "followpin_segments": 8,
                 "stripe_segments": 4, "other_segments": 0,
                 "stripe_layers": ["met4", "met5"], "vias": 21},
            ],
        },
    }
    if power is not None:
        p.update(power)
    return {"schema_version": 1, "status": "ok", "stage_reached": "route", "power": p}


def sta_env(**over: object) -> dict:
    base = {
        "geometry_source": "routed",
        "timing_status": "constrained",
        "worst_slack_ns": 15.2,
        "worst_hold_slack_ns": 0.12,
        "total_negative_slack_ns": 0.0,
    }
    base.update(over)
    return {"schema_version": 1, **base}


def drc_env(**over: object) -> dict:
    return {"schema_version": 1, "status": "clean", "violation_count": 0, **over}


def lvs_env(power_status: str = "match", unchecked: list | None = None,
            **over: object) -> dict:
    # power_connectivity carries unchecked_expected_pins in every envelope
    # the pinned klt emits, so the fixture matches that shape by default
    return {
        "schema_version": 1,
        "status": "match",
        "power_connectivity": {
            "status": power_status,
            "reason": None,
            "unchecked_expected_pins": [] if unchecked is None else unchecked,
        },
        **over,
    }


def erc_env(nets: list | None = None, coverage: dict | None = None,
            findings: list | None = None, **over: object) -> dict:
    return {
        "schema_version": 2,
        "erc_status": "clean",
        "erc_finding_count": 0,
        "nets": nets if nets is not None else [
            {"name": "VDD", "matched_islands": 1, "expected_islands": 1},
            {"name": "VSS", "matched_islands": 1, "expected_islands": 1},
        ],
        "erc_coverage": coverage if coverage is not None else {
            "scope": "connectivity",
            "checked": ['erc.missing_tie:["nwell_tap"]'],
            "skipped": [],
        },
        "erc_findings": findings if findings is not None else [],
        **over,
    }


def passing_result() -> dict:
    return {
        "synthesize": synth_env(),
        "place-and-route": par_env(),
        "sta": sta_env(),
        "drc": drc_env(),
        "lvs": lvs_env(),
        "erc": erc_env(),
    }


class Passing(unittest.TestCase):
    def test_all_six_pass(self):
        self.assertEqual(grade_result(passing_result()), [])


class EnginePin(unittest.TestCase):
    """The klayout engine probe (#26): klt at its pin with a drifted engine
    must fail the probe, which writes no record."""

    def test_engine_at_the_pin(self):
        info = {"version": "0.9.2", "klayout_version": "0.30.12",
                "klayout_version_expected": "0.30.12"}
        self.assertIsNone(engine_pin_error(info, "0.30.12"))

    def test_only_the_engine_moved(self):
        info = {"version": "0.9.2", "klayout_version": "0.30.13",
                "klayout_version_expected": "0.30.12"}
        why = engine_pin_error(info, "0.30.12")
        self.assertIsNotNone(why)
        self.assertIn("klayout 0.30.13", why)
        self.assertIn("pin 0.30.12", why)

    def test_engine_unreadable(self):
        for info in (None, [], {}, {"klayout_version": None},
                     {"klayout_version": 0.30}, {"klayout_version": ""}):
            with self.subTest(info=info):
                self.assertIn("no klayout_version", engine_pin_error(info, "0.30.12"))

    def test_pin_is_stated_and_meets_the_floor(self):
        # the probe reads PIN_KLAYOUT from the one pin source; the exact pin
        # never sits below the floor klt declares
        p = pins(repo_root())
        parts = lambda v: [int(x) for x in v.split(".")]  # noqa: E731
        self.assertGreaterEqual(parts(p["PIN_KLAYOUT"]), parts(p["PIN_KLAYOUT_MIN"]))


class NegativeSynthesize(unittest.TestCase):
    def test_unexpected_latch(self):
        f = grade_envelope("synthesize", synth_env(unexpected_latches=1))
        self.assertTrue(any("unexpected_latches" in x for x in f))

    def test_comb_loop_and_multi_driven(self):
        env = synth_env(comb_loops=2, multi_driven=1)
        f = grade_envelope("synthesize", env)
        self.assertTrue(any("comb_loops" in x for x in f))
        self.assertTrue(any("multi_driven" in x for x in f))


class NegativePlaceAndRoute(unittest.TestCase):
    def test_partial_placed_audit(self):
        env = par_env(power={"placed": {"evidence": "def", "status": "partial",
                                        "missing": ["fillers", "pdn_vias"],
                                        "tapcells": 24}})
        f = grade_envelope("place-and-route", env)
        self.assertTrue(any("power.placed.status" in x and "'partial'" in x for x in f))
        # fillers missing -> missing[] surfaced in the reason
        self.assertTrue(any("fillers" in x for x in f))

    def test_no_pdn(self):
        f = grade_envelope("place-and-route", par_env(power={"pdn": False}))
        self.assertTrue(any("power.pdn" in x for x in f))

    def test_unnamed_tapcell_master(self):
        f = grade_envelope("place-and-route", par_env(power={"tapcell_master": None}))
        self.assertTrue(any("tapcell_master" in x for x in f))

    def test_zero_placed_tapcells(self):
        env = par_env(power={"placed": {"status": "complete", "tapcells": 0}})
        f = grade_envelope("place-and-route", env)
        self.assertTrue(any("power.placed.tapcells" in x for x in f))
        # "ok" is not a status the audit ever emits; it must not pass either
        env = par_env(power={"placed": {"status": "ok", "tapcells": 5}})
        f = grade_envelope("place-and-route", env)
        self.assertTrue(any('power.placed.status' in x for x in f))


class NegativeSta(unittest.TestCase):
    def test_negative_slack(self):
        f = grade_envelope("sta", sta_env(worst_slack_ns=-0.5))
        self.assertTrue(any("worst_slack_ns" in x for x in f))

    def test_unconstrained_sentinel(self):
        # OpenSTA's unconstrained sentinel is a *positive* 1e+39: the gate
        # must refuse it via timing_status, not bless it as closed timing
        env = sta_env(timing_status="unconstrained", worst_slack_ns=1e39)
        f = grade_envelope("sta", env)
        self.assertTrue(any("timing_status" in x for x in f))

    def test_negative_hold_slack(self):
        f = grade_envelope("sta", sta_env(worst_hold_slack_ns=-0.01))
        self.assertTrue(any("worst_hold_slack_ns" in x for x in f))


class NegativeDrc(unittest.TestCase):
    def test_violations(self):
        f = grade_envelope("drc", drc_env(status="violations", violation_count=3))
        self.assertTrue(any("status" in x for x in f))
        self.assertTrue(any("violation_count" in x for x in f))


class NegativeLvs(unittest.TestCase):
    def test_signal_match_power_mismatch(self):
        f = grade_envelope("lvs", lvs_env(power_status="mismatch"))
        self.assertTrue(any("power_connectivity.status" in x for x in f))

    def test_power_unchecked(self):
        env = lvs_env(power_status="unchecked")
        env["power_connectivity"]["reason"] = "reference.form is not gate-level-verilog"
        f = grade_envelope("lvs", env)
        self.assertTrue(any("power_connectivity.status" in x for x in f))

    def test_signal_mismatch(self):
        f = grade_envelope("lvs", lvs_env() | {"status": "mismatch"})
        self.assertTrue(any("status" in x and "power" not in x for x in f))

    def test_unchecked_expected_pins(self):
        # status says match, yet the declared VNB expectation resolved zero
        # rows: a check that could not run must not read as one that passed
        # (the exact power_connectivity shape of record 20261122T200938Z)
        env = lvs_env(unchecked=["VNB"])
        f = grade_envelope("lvs", env)
        self.assertTrue(any("unchecked_expected_pins" in x for x in f))
        self.assertTrue(any("VNB" in x for x in f))

    def test_unchecked_expected_pins_empty_passes(self):
        self.assertEqual(grade_envelope("lvs", lvs_env()), [])

    def test_unchecked_expected_pins_key_absent(self):
        # envelope shape drift: without the key the gate cannot tell checked
        # from unchecked, so it fails instead of silently passing
        env = lvs_env()
        del env["power_connectivity"]["unchecked_expected_pins"]
        f = grade_envelope("lvs", env)
        self.assertTrue(any("unchecked_expected_pins" in x for x in f))

    def test_typoed_expected_pin(self):
        # a typo'd expected_nets key lands in unchecked_expected_pins and
        # must fail the gate naming the pin
        env = lvs_env(unchecked=["VPWRX"])
        f = grade_envelope("lvs", env)
        self.assertTrue(any("VPWRX" in x for x in f))


class NegativeErc(unittest.TestCase):
    def test_absent_supply_row(self):
        # output nets[] rows key on name and never echo kind: dropping the
        # VSS row (as a kind-filtered reader would) must fail, not pass
        nets = [{"name": "VDD", "matched_islands": 1, "expected_islands": 1}]
        f = grade_envelope("erc", erc_env(nets=nets))
        self.assertTrue(any("no row named 'VSS'" in x for x in f))

    def test_supply_row_identified_by_kind_only(self):
        # a row carrying kind but not the name must not satisfy the gate
        nets = [
            {"name": "VDD", "matched_islands": 1, "expected_islands": 1},
            {"kind": "supply", "matched_islands": 1},
        ]
        f = grade_envelope("erc", erc_env(nets=nets))
        self.assertTrue(any("no row named 'VSS'" in x for x in f))

    def test_two_islands(self):
        nets = [
            {"name": "VDD", "matched_islands": 2, "expected_islands": 1},
            {"name": "VSS", "matched_islands": 1, "expected_islands": 1},
        ]
        f = grade_envelope("erc", erc_env(nets=nets))
        self.assertTrue(any("VDD" in x and "matched_islands" in x for x in f))

    def test_skipped_tie_check(self):
        # degenerate_tap_declaration: the tie lands in skipped, not checked
        cov = {"checked": [],
               "skipped": [{"id": 'erc.missing_tie:["nwell_tap"]',
                            "reason": "degenerate_tap_declaration"}]}
        f = grade_envelope("erc", erc_env(coverage=cov))
        self.assertTrue(any("erc_coverage.checked" in x for x in f))
        self.assertTrue(any("erc_coverage.skipped" in x for x in f))

    def test_missing_tie_finding(self):
        findings = [{"rule": "erc.missing_tie", "description": "no tap contact drawn",
                     "net": "VDD"}]
        f = grade_envelope("erc", erc_env(findings=findings, erc_finding_count=1,
                                          erc_status="violations"))
        self.assertTrue(any("erc_findings" in x for x in f))
        self.assertTrue(any("erc_status" in x for x in f))

    def test_supply_short_finding(self):
        findings = [{"rule": "erc.supply_short", "net": "VDD", "other_net": "VSS"}]
        f = grade_envelope("erc", erc_env(findings=findings, erc_finding_count=1))
        self.assertTrue(any("erc_findings" in x for x in f))

    def test_clean_partial(self):
        # clean_partial = a tie was skipped: must not pass a clean gate
        f = grade_envelope("erc", erc_env(erc_status="clean_partial"))
        self.assertTrue(any("erc_status" in x for x in f))


class MissingStages(unittest.TestCase):
    def test_error_stage_fails_gates(self):
        r = passing_result()
        r["erc"] = {"_error": "skipped: upstream stage failed"}
        f = grade_result(r)
        self.assertEqual(len(f), 1)
        self.assertIn("erc", f[0])

    def test_absent_stage_fails_gates(self):
        r = passing_result()
        del r["lvs"]
        self.assertEqual(len(grade_result(r)), 1)

    def test_every_verb_graded(self):
        r = {v: {"_error": "x"} for v in VERBS}
        self.assertEqual(len(grade_result(r)), len(VERBS))


GNU_BANNER = (b"/* Generated by Yosys 0.67+post (git sha1 b8e7da6f, Release, "
              b"GNU /usr/bin/c++ 13.3.0) */\n")
CLANG_BANNER = (b"/* Generated by Yosys 0.67+post (git sha1 b8e7da6f, Release, "
                b"Clang /usr/bin/c++ 18.1.3) */\n")


class NetlistHashNormalisation(unittest.TestCase):
    """issue #32: netlist_sha256 covers the Yosys banner, which names the
    compiler that built Yosys -- two builds at the same pinned version hash
    differently for byte-identical netlist content. The normalised hash
    strips a *leading* banner so cross-build comparisons are well defined."""

    def test_banner_only_difference_normalises_equal(self):
        body = b"module smoke(clk);\n  input clk;\nendmodule\n"
        gnu, clang = GNU_BANNER + body, CLANG_BANNER + body
        self.assertNotEqual(hashlib.sha256(gnu).hexdigest(),
                            hashlib.sha256(clang).hexdigest())
        self.assertEqual(normalised_netlist_sha256(gnu),
                         normalised_netlist_sha256(clang))

    def test_no_banner_hashes_verbatim(self):
        data = b"module smoke(clk);\n  input clk;\nendmodule\n"
        self.assertEqual(normalised_netlist_sha256(data),
                         hashlib.sha256(data).hexdigest())

    def test_mid_file_banner_is_kept(self):
        # only a leading banner is Yosys's; a comment later in the file is
        # netlist content and must stay in the hash
        data = (b"module smoke(clk);\n" + GNU_BANNER + b"endmodule\n")
        self.assertEqual(normalised_netlist_sha256(data),
                         hashlib.sha256(data).hexdigest())


class NetlistHashNote(unittest.TestCase):
    def _envelope(self, path):
        return {"netlist_sha256": "ab" * 32,
                "netlist_path": {"path": path, "scope": "repo"}}

    def test_note_pairs_raw_normalised_and_build_string(self):
        with tempfile.TemporaryDirectory() as d:
            nl = Path(d) / "smoke_synth.v"
            nl.write_bytes(GNU_BANNER + b"module smoke;\nendmodule\n")
            note = netlist_hash_note(self._envelope(str(nl)), Path(d),
                                     "Yosys 0.67+post (GNU c++ 13.3.0)")
        self.assertIn("netlist_sha256=" + "ab" * 32, note)
        self.assertIn("netlist_sha256_banner_normalised=" + hashlib.sha256(
            b"module smoke;\nendmodule\n").hexdigest(), note)
        self.assertIn("GNU c++ 13.3.0", note)

    def test_unreadable_netlist_says_not_recorded(self):
        note = netlist_hash_note(self._envelope("no/such/file.v"), Path("/"),
                                 "Yosys 0.67+post")
        self.assertIn("not recorded", note)

    def test_envelope_without_hash_says_not_recorded(self):
        note = netlist_hash_note({}, Path("/"), "Yosys 0.67+post")
        self.assertIn("not recorded", note)


if __name__ == "__main__":
    unittest.main()
