#!/usr/bin/env bash
# Pins for the verification harness; this file is the single source of truth
# for them (verification/README.md points here rather than copying values).
#
#   scripts/setup-env.sh --check   verify cocotb + iverilog against the pins
#                                  below; exit 1 on mismatch
#
# Copied by pattern from sky130-riscv-soc's scripts/setup-env.sh (source
# commit in verification/README.md), cut down to the two tools the smoke
# harness needs. Nothing is fetched and no tool is installed: tools are only
# checked. PDK, synthesis and P&R tool pins are added here when first used.
set -euo pipefail

# ---- pins -----------------------------------------------------------------
PIN_COCOTB="2.0.1"      # every verification/Makefile target needs it; required here
PIN_IVERILOG="13.0"     # the RTL simulator of every verification/Makefile target
# ---------------------------------------------------------------------------

FAILED=0
ok()   { printf 'ok    %-10s %s\n' "$1" "$2"; }
fail() { printf 'FAIL  %-10s %s\n' "$1" "$2" >&2; FAILED=1; }

# check_tool NAME EXPECT CMD... : run the version probe, expect EXPECT in line 1
check_tool() {
    local name="$1" expect="$2"; shift 2
    local out
    if ! command -v "$1" >/dev/null 2>&1; then fail "$name" "'$1' not on PATH (pinned ${expect})"; return; fi
    out="$("$@" 2>&1 | head -n 1)" || true
    if [[ "$out" == *"$expect"* ]]; then ok "$name" "$out"
    else fail "$name" "got '${out}', pinned '${expect}'"; fi
}

check_cocotb() {
    local got
    got="$(python3 -c 'import cocotb;print(cocotb.__version__)' 2>/dev/null || true)"
    if [[ "$got" == "$PIN_COCOTB" ]]; then ok cocotb "$got"
    else fail cocotb "got '${got:-not installed}', pinned ${PIN_COCOTB}"; fi
}

run_check() {
    check_tool iverilog "version ${PIN_IVERILOG} " iverilog -V
    check_cocotb
    if [[ "$FAILED" -ne 0 ]]; then echo "environment does not match the pins" >&2; exit 1; fi
    echo "environment matches the pins"
}

case "${1:-}" in
    --check|"") run_check ;;
    *)          echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
