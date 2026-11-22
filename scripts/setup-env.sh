#!/usr/bin/env bash
# Pins for the verification harness and the implementation flow; this file is
# the single source of truth for them (verification/README.md and flow/README.md
# point here rather than copying values).
#
#   scripts/setup-env.sh --check       verify cocotb + iverilog against the
#                                      pins below; exit 1 on mismatch. The
#                                      hosted CI smoke job runs exactly this
#                                      on a runner with no PDK, klt, Yosys or
#                                      OpenROAD installed, so this mode keeps
#                                      verifying only the simulation pins.
#   scripts/setup-env.sh --check-flow  the simulation pins above plus every
#                                      implementation-flow pin (PDK revision,
#                                      klt version, the klayout engine it
#                                      loads + the commands
#                                      layout/toolchain.json requires, Yosys,
#                                      OpenROAD); exit 1 on any mismatch or
#                                      absence -- never a warn/skip. The
#                                      flow-smoke target runs this first.
#   scripts/setup-env.sh --fetch-pdk   fetch sky130A at the pinned open_pdks
#                                      revision into ${PDK_ROOT:-$HOME/.ciel}
#                                      via ciel (run through a throwaway uvx
#                                      environment), then --check-flow.
#   scripts/setup-env.sh --klt-bin     print how runners invoke the pinned
#                                      klt (a single space-separated command
#                                      line): .venv/bin/klt when it carries
#                                      the pin, else a PATH klt whose version
#                                      matches the pin, else
#                                      `uvx --from klayout-tools==$PIN_KLT
#                                      --with klayout==$PIN_KLAYOUT`.
#
# The check modes fetch nothing and install no tool: tools are only checked.
# Copied by pattern from sky130-riscv-soc's scripts/setup-env.sh (source
# commit in verification/README.md), extended with the flow pins that repo
# already carries. Dispatch workers carry a rotating dev klt on PATH and
# forbid mutating host tools, so klt is resolved per --klt-bin above rather
# than assumed to be the pin.
set -euo pipefail

# ---- simulation pins (hosted CI verifies these; --check) -------------------
PIN_COCOTB="2.0.1"      # every verification/Makefile target needs it; required here
PIN_IVERILOG="13.0"     # the RTL simulator of every verification/Makefile target
# ---- implementation-flow pins (--check-flow verifies these) ----------------
PIN_PDK_FAMILY="sky130"
PIN_PDK_VARIANT="sky130A"
PIN_OPEN_PDKS_REV="f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7"
PIN_CIEL="3.1.0"        # PDK fetcher for --fetch-pdk, via uvx
PIN_KLT="0.9.2"         # PyPI release klayout-tools; layout/toolchain.json states the same pin
PIN_KLAYOUT_MIN="0.30"  # klayout package floor that klayout-tools==0.9.2 declares
PIN_KLAYOUT="0.30.12"   # exact klayout engine: the version klayout-tools==0.9.2 was tested
                        # against (`klt version --format json`'s klayout_version_expected).
                        # klt declares only the floor above, so an install that does not
                        # state this pin resolves the newest klayout release instead.
PIN_YOSYS="0.67+post"
PIN_YOSYS_SHA="b8e7da6f40ae8f552c116bf6c359b07c6533e159"
PIN_OPENROAD="26Q3-1510-g6cb3f2b704"
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PDK_ROOT="${PDK_ROOT:-$HOME/.ciel}"

fetch_pdk() {
    echo "fetching ${PIN_PDK_VARIANT} @ open_pdks ${PIN_OPEN_PDKS_REV} into ${PDK_ROOT}"
    uvx --from "ciel==${PIN_CIEL}" ciel enable --pdk-family "${PIN_PDK_FAMILY}" \
        --pdk-root "${PDK_ROOT}" "${PIN_OPEN_PDKS_REV}"
}

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

check_pdk() {
    local src="${PDK_ROOT}/${PIN_PDK_VARIANT}/SOURCES" got
    if [[ ! -r "$src" ]]; then
        fail pdk "no ${src}; run scripts/setup-env.sh --fetch-pdk (PDK_ROOT=${PDK_ROOT})"
        return
    fi
    got="$(awk '/^open_pdks/ {print $2; exit}' "$src")"
    if [[ "$got" == "$PIN_OPEN_PDKS_REV" ]]; then ok pdk "${PIN_PDK_VARIANT} open_pdks ${got}"
    else fail pdk "open_pdks ${got:-unknown}, pinned ${PIN_OPEN_PDKS_REV}"; fi
}

# klt_version_of CMD... : the version token of `CMD... --version` ("" if none)
klt_version_of() {
    "$@" --version 2>/dev/null | head -n 1 | sed -n 's/^klt \([0-9][^ ]*\).*/\1/p' || true
}

# klt_version_field FIELD CMD... : one string field of `CMD... version --format
# json` ("" when the command fails or the field is absent or not a string)
klt_version_field() {
    local field="$1"; shift
    "$@" version --format json 2>/dev/null | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)[sys.argv[1]]
except Exception:
    v = None
if isinstance(v, str):
    print(v)
' "$field" || true
}

# resolve_klt : print the command line that runs klt at PIN_KLT. .venv first
# (the cold-start venv), then a PATH klt that already carries the pin (a
# dev build does not -- the dispatch-worker case), then the pinned PyPI
# release through uvx, which provisions nothing on the host. The uvx form
# states PIN_KLAYOUT too: klt declares only a floor on the klayout engine.
resolve_klt() {
    if [[ -x "${REPO_ROOT}/.venv/bin/klt" ]] \
        && [[ "$(klt_version_of "${REPO_ROOT}/.venv/bin/klt")" == "${PIN_KLT}" ]]; then
        printf '%s\n' "${REPO_ROOT}/.venv/bin/klt"
    elif command -v klt >/dev/null 2>&1 \
        && [[ "$(klt_version_of klt)" == "${PIN_KLT}" ]]; then
        printf '%s\n' "klt"
    else
        printf '%s\n' "uvx --from klayout-tools==${PIN_KLT} --with klayout==${PIN_KLAYOUT} klt"
    fi
}

# toolchain_field KEY : one string field of layout/toolchain.json ("" if absent)
toolchain_field() {
    python3 -c '
import json, sys
try:
    v = json.load(open(sys.argv[1]))[sys.argv[2]]
except Exception:
    v = None
if isinstance(v, str):
    print(v)
' "${REPO_ROOT}/layout/toolchain.json" "$1" || true
}

check_klt() {
    local cmd out
    cmd="$(resolve_klt)"
    # shellcheck disable=SC2086
    out="$(klt_version_of $cmd)" || true
    if [[ "$out" == "${PIN_KLT}" ]]; then
        ok klt "${out} (via ${cmd})"
    else
        fail klt "got '${out:-no version}', pinned ${PIN_KLT} (resolved: ${cmd})"
        return
    fi
    # the klayout engine this klt loads must be the exact pin, and the pin
    # must be the engine klt itself was tested against: klt declares only a
    # floor, so without both checks an install drifts under a fixed PIN_KLT
    local engine expected
    # shellcheck disable=SC2086
    engine="$(klt_version_field klayout_version $cmd)"
    # shellcheck disable=SC2086
    expected="$(klt_version_field klayout_version_expected $cmd)"
    if [[ -z "$engine" ]]; then
        fail klayout "no klayout_version in \`${cmd} version --format json\` (pinned ${PIN_KLAYOUT})"
    elif [[ "$engine" == "${PIN_KLAYOUT}" ]]; then
        ok klayout "${engine} (loaded by ${cmd})"
    else
        fail klayout "got '${engine}', pinned ${PIN_KLAYOUT} (loaded by ${cmd}); install klayout==${PIN_KLAYOUT} into that klt's environment"
    fi
    if [[ -z "$expected" ]]; then
        fail klt-tested "no klayout_version_expected in \`${cmd} version --format json\`; cannot tell which klayout klt ${PIN_KLT} was tested against"
    elif [[ "$expected" != "${PIN_KLAYOUT}" ]]; then
        fail klt-tested "klt ${PIN_KLT} was tested against klayout ${expected}, but PIN_KLAYOUT is ${PIN_KLAYOUT}; move the pin with PIN_KLT"
    else
        ok klt-tested "klt ${PIN_KLT} was tested against klayout ${expected}"
    fi
    # layout/toolchain.json states the same engine pin; it must not drift
    out="$(toolchain_field klayout_package_pin)"
    if [[ "$out" == "${PIN_KLAYOUT}" ]]; then
        ok toolchain "layout/toolchain.json klayout_package_pin ${out}"
    else
        fail toolchain "layout/toolchain.json klayout_package_pin '${out:-absent}', PIN_KLAYOUT ${PIN_KLAYOUT}"
    fi
    # every command layout/toolchain.json requires must exist in klt --help
    local help_cmds want missing=""
    # shellcheck disable=SC2086
    help_cmds="$($cmd --help 2>/dev/null \
        | sed -n '/positional arguments:/,/options:/p' \
        | grep -oE '^    [a-z][a-z0-9-]+' | tr -d ' ' || true)"
    while IFS= read -r want; do
        [[ -z "$want" ]] && continue
        if ! grep -qx "$want" <<<"$help_cmds"; then
            missing="${missing}${missing:+ }${want}"
        fi
    done < <(python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    for c in json.load(f)["klt_required_commands"]:
        print(c)
' "${REPO_ROOT}/layout/toolchain.json")
    if [[ -n "$missing" ]]; then
        fail klt-commands "klt ${PIN_KLT} lacks required command(s): ${missing}"
    else
        ok klt-commands "$(python3 -c '
import json, sys
print(" ".join(json.load(open(sys.argv[1]))["klt_required_commands"]))
' "${REPO_ROOT}/layout/toolchain.json")"
    fi
}

run_check() {
    check_tool iverilog "version ${PIN_IVERILOG} " iverilog -V
    check_cocotb
    if [[ "$FAILED" -ne 0 ]]; then echo "environment does not match the pins" >&2; exit 1; fi
    echo "environment matches the pins"
}

run_check_flow() {
    check_tool iverilog "version ${PIN_IVERILOG} " iverilog -V
    check_cocotb
    check_pdk
    check_klt
    check_tool yosys "Yosys ${PIN_YOSYS} (git sha1 ${PIN_YOSYS_SHA}" yosys -V
    check_tool openroad "${PIN_OPENROAD}" openroad -version
    if [[ "$FAILED" -ne 0 ]]; then echo "environment does not match the flow pins" >&2; exit 1; fi
    echo "environment matches the flow pins"
}

case "${1:-}" in
    --check|"") run_check ;;
    --check-flow) run_check_flow ;;
    --fetch-pdk) fetch_pdk; run_check_flow ;;
    --klt-bin) resolve_klt ;;
    *)          echo "usage: $0 [--check|--check-flow|--fetch-pdk|--klt-bin]" >&2; exit 2 ;;
esac
