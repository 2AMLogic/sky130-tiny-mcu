#!/usr/bin/env bash
# test-setup-env.sh — fixture test for setup-env.sh's check modes (#21, #26).
#
# Hermetic: every tool is a stub on a throwaway PATH, the PDK is a throwaway
# PDK_ROOT, and the cocotb probe is a stub python3 that answers only that one
# invocation. Each case states its whole environment explicitly (CASE_ENV).
# Asserts BOTH outcomes of each mode:
#   --check      unchanged by the flow pins — passes with only the simulation
#                stubs present (the hosted CI shape: no PDK, klt, Yosys or
#                OpenROAD anywhere), fails on a sim-pin mismatch
#   --check-flow the simulation pins plus every flow pin; fails — never 0,
#                never warn-only — when the PDK, klt (version, the klayout
#                engine it loads, the engine it was tested against, or
#                required commands), layout/toolchain.json's engine pin,
#                Yosys or OpenROAD is missing or mismatched, and passes only
#                when all of them match the pins
#   --klt-bin    the resolution order: .venv/bin/klt at the pin, then a PATH
#                klt at the pin, then uvx --from klayout-tools==<pin>
#                --with klayout==<engine pin>
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$here/../setup-env.sh"
if [[ ! -x "$setup" ]]; then
  echo "test-setup-env: missing executable $setup" >&2
  exit 2
fi

work="$(mktemp -d)"
repo_root="$(cd "$here/../.." && pwd)"
# The klt-resolution cases must see the repo the way a fresh checkout sees
# it: no .venv. A real cold-start .venv (gitignored) is stashed for the
# test's duration and restored on exit, whatever the exit path.
stashed_venv=0
if [[ -e "$repo_root/.venv" ]]; then
  mv "$repo_root/.venv" "$work/venv-stash"
  stashed_venv=1
fi
cleanup() {
  [[ "$stashed_venv" == 1 ]] && mv "$work/venv-stash" "$repo_root/.venv"
  rm -rf "$work"
}
trap cleanup EXIT

pass=0
fail=0
MODE=()
CASE_ENV=()

run_case() { # run_case <want-exit> <desc>  (SETUP overrides the script under test)
  local want="$1" desc="$2" got=0
  ( env PATH="$STUB_BIN:/usr/bin:/bin" HOME="$work/home" "${CASE_ENV[@]}" \
      "${SETUP:-$setup}" "${MODE[@]:---check}" ) >"$work/last-case.log" 2>&1 || got=$?
  if [[ "$got" -eq "$want" ]]; then
    pass=$((pass + 1))
    echo "PASS: $desc (exit $got)"
  else
    fail=$((fail + 1))
    echo "FAIL: $desc — expected exit $want, got $got" >&2
    sed 's/^/    | /' "$work/last-case.log" >&2
  fi
}

# log_has <desc> <grep -E pattern> : the last run's log must contain the
# pattern, so a case is known to fail (or pass) for the reason it names
log_has() {
  if grep -qE -- "$2" "$work/last-case.log"; then
    pass=$((pass + 1)); echo "PASS: $1"
  else
    fail=$((fail + 1)); echo "FAIL: $1 — no line matches '$2' in:" >&2
    sed 's/^/    | /' "$work/last-case.log" >&2
  fi
}

resolve_case() { # resolve_case <desc> <want-substring-or-equal>
  local desc="$1" want="$2" got
  got="$(env PATH="$STUB_BIN:/usr/bin:/bin" HOME="$work/home" "${CASE_ENV[@]}" \
      "$setup" --klt-bin)" || true
  if [[ "$want" == =* ]]; then
    want="${want#=}"
    if [[ "$got" == "$want" ]]; then
      pass=$((pass + 1)); echo "PASS: $desc ($got)"
    else
      fail=$((fail + 1)); echo "FAIL: $desc — expected exactly '$want', got '$got'" >&2
    fi
  elif [[ "$got" == *"$want"* ]]; then
    pass=$((pass + 1)); echo "PASS: $desc ($got)"
  else
    fail=$((fail + 1)); echo "FAIL: $desc — expected '$want' in '$got'" >&2
  fi
}

# ---- stub toolchain --------------------------------------------------------
STUB_BIN="$work/bin"
mkdir -p "$STUB_BIN" "$work/home"

stub() { # stub <name> <script...>
  local name="$1"; shift
  { printf '#!/usr/bin/env bash\n'; for l in "$@"; do printf '%s\n' "$l"; done; } \
      >"$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
}

stub iverilog 'if [[ "${1:-}" == "-V" ]]; then echo "Icarus Verilog version ${IVERILOG_V:-13.0} (stable) (v13_0)"; fi'
stub yosys    'if [[ "${1:-}" == "-V" ]]; then echo "Yosys ${YOSYS_V:-0.67+post} (git sha1 ${YOSYS_SHA:-b8e7da6f40ae8f552c116bf6c359b07c6533e159}, Release)"; fi'
stub openroad 'if [[ "${1:-}" == "-version" ]]; then echo "${OPENROAD_V:-26Q3-1510-g6cb3f2b704}"; fi'
# klt: --version honors KLT_V; --help lists KLT_CMDS (comma-separated) at the
# 4-space indent the required-commands check parses; `version --format json`
# reports the klayout engine KLT_KLAYOUT_V loaded and the one klt was tested
# against, KLT_KLAYOUT_EXPECTED (either `none` emits JSON null)
stub klt 'if [[ "${1:-}" == "--version" ]]; then echo "klt ${KLT_V:-0.9.2}"; exit 0; fi
if [[ "${1:-}" == "version" && "${2:-}" == "--format" && "${3:-}" == "json" ]]; then
  v="${KLT_KLAYOUT_V:-0.30.12}"; e="${KLT_KLAYOUT_EXPECTED:-0.30.12}"
  [[ "$v" == none ]] && v=null || v="\"$v\""
  [[ "$e" == none ]] && e=null || e="\"$e\""
  printf "{\"version\": \"%s\", \"klayout_version\": %s, \"klayout_version_expected\": %s}\n" "${KLT_V:-0.9.2}" "$v" "$e"
  exit 0
fi
if [[ "${1:-}" == "--help" ]]; then
  printf "usage: klt [-h] <command> ...\n\npositional arguments:\n"
  IFS=","; for c in ${KLT_CMDS:-synthesize,place-and-route,sta,drc,lvs,erc}; do
    printf "    %-20s stub command\n" "$c"
  done
  printf "\noptions:\n  -h  help\n"
fi'
# python3: answer only the cocotb probe inline; delegate everything else
cat >"$STUB_BIN/python3" <<'PY'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" && "${2:-}" == "import cocotb;print(cocotb.__version__)" ]]; then
  if [[ -n "${COCOTB_V:-}" ]]; then echo "$COCOTB_V"; exit 0; else exit 1; fi
fi
exec /usr/bin/python3 "$@"
PY
chmod +x "$STUB_BIN/python3"

fake_pdk() { # fake_pdk <rev|absent>
  rm -rf "$work/pdk"
  if [[ "$1" != absent ]]; then
    mkdir -p "$work/pdk/sky130A"
    printf 'open_pdks %s\nskywater-pdk ...\n' "$1" >"$work/pdk/sky130A/SOURCES"
  fi
}

SIM_OK=(COCOTB_V=2.0.1)
FLOW_OK=(COCOTB_V=2.0.1 PDK_ROOT="$work/pdk")

# ---- --check: unchanged by the flow pins ------------------------------------
MODE=()
CASE_ENV=("${SIM_OK[@]}")
run_case 0 "--check passes with only sim stubs (hosted CI shape: no PDK/klt/yosys/openroad, no PDK_ROOT)"
CASE_ENV=(COCOTB_V=)
run_case 1 "--check fails when cocotb is missing"
CASE_ENV=(COCOTB_V=2.0.1 IVERILOG_V=11.0)
run_case 1 "--check fails on an iverilog version mismatch"

# ---- --check-flow: fail, never skip, on every flow-pin problem ---------------
MODE=(--check-flow)
fake_pdk absent
CASE_ENV=("${FLOW_OK[@]}")
run_case 1 "--check-flow fails with no PDK_ROOT (never warn-only)"
CASE_ENV=("${FLOW_OK[@]}" PDK_ROOT="$work/nowhere")
run_case 1 "--check-flow fails when the PDK is absent"
fake_pdk f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
CASE_ENV=("${FLOW_OK[@]}" KLT_V=0.9.3.dev3146)
run_case 1 "--check-flow fails on a klt version mismatch (dispatch-worker dev build)"
CASE_ENV=("${FLOW_OK[@]}" KLT_CMDS=synthesize,drc)
run_case 1 "--check-flow fails when a klt_required_commands entry is missing"
# the klayout engine pin (#26): klt stays at its pin, only the engine moves
CASE_ENV=("${FLOW_OK[@]}" KLT_KLAYOUT_V=0.30.13)
run_case 1 "--check-flow fails when only the klayout engine differs (0.30.13 under klt 0.9.2)"
log_has "  ...naming the engine, both versions" "^FAIL  klayout +got '0\\.30\\.13', pinned 0\\.30\\.12"
log_has "  ...with the klt version check itself ok" "^ok    klt "
CASE_ENV=("${FLOW_OK[@]}" KLT_KLAYOUT_V=none)
run_case 1 "--check-flow fails when the engine version cannot be read"
log_has "  ...saying so, never skipping" "^FAIL  klayout +no klayout_version"
CASE_ENV=("${FLOW_OK[@]}" KLT_KLAYOUT_EXPECTED=0.30.14)
run_case 1 "--check-flow fails when the engine klt was tested against is not the pin"
log_has "  ...naming both versions" "^FAIL  klt-tested +klt 0\\.9\\.2 was tested against klayout 0\\.30\\.14, but PIN_KLAYOUT is 0\\.30\\.12"
CASE_ENV=("${FLOW_OK[@]}" KLT_KLAYOUT_EXPECTED=none)
run_case 1 "--check-flow fails when klt does not say which engine it was tested against"
# layout/toolchain.json states the same engine pin: a drifted COPY of the pin
# files must fail (the real file is never touched)
drift="$work/repo"
mkdir -p "$drift/scripts" "$drift/layout"
cp "$setup" "$drift/scripts/setup-env.sh"
sed -E 's/("klayout_package_pin": ")[^"]*/\10.0.0-drift/' \
    "$repo_root/layout/toolchain.json" >"$drift/layout/toolchain.json"
grep -q '"klayout_package_pin": "0.0.0-drift"' "$drift/layout/toolchain.json"
CASE_ENV=("${FLOW_OK[@]}")
SETUP="$drift/scripts/setup-env.sh" \
    run_case 1 "--check-flow fails when toolchain.json's klayout_package_pin drifts from PIN_KLAYOUT"
log_has "  ...naming both values" "^FAIL  toolchain +layout/toolchain\\.json klayout_package_pin '0\\.0\\.0-drift', PIN_KLAYOUT 0\\.30\\.12"
# klt_required_commands removed from a COPY of the manifest: the check must
# fail naming the field, not pass on an empty list
nolist="$work/repo-nolist"
mkdir -p "$nolist/scripts" "$nolist/layout"
cp "$setup" "$nolist/scripts/setup-env.sh"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
del d["klt_required_commands"]
json.dump(d, open(sys.argv[2], "w"))
' "$repo_root/layout/toolchain.json" "$nolist/layout/toolchain.json"
CASE_ENV=("${FLOW_OK[@]}")
SETUP="$nolist/scripts/setup-env.sh" \
    run_case 1 "--check-flow fails when toolchain.json has no klt_required_commands"
log_has "  ...naming the field" "^FAIL  klt-commands +.*klt_required_commands"
CASE_ENV=("${FLOW_OK[@]}" YOSYS_V=0.44)
run_case 1 "--check-flow fails on a Yosys mismatch"
CASE_ENV=("${FLOW_OK[@]}" OPENROAD_V=24Q1-g000000)
run_case 1 "--check-flow fails on an OpenROAD mismatch"
CASE_ENV=("${FLOW_OK[@]}")
run_case 0 "--check-flow passes when every pin matches"
log_has "  ...listing all six required commands" "^ok    klt-commands +([a-z0-9-]+ ){5}[a-z0-9-]+$"
log_has "  ...reporting the klayout engine at the pin" "^ok    klayout +0\\.30\\.12 \\(loaded by klt\\)"
CASE_ENV=(COCOTB_V= PDK_ROOT="$work/pdk")
run_case 1 "--check-flow still verifies the simulation pins (cocotb missing)"

# ---- --klt-bin resolution order ----------------------------------------------
fake_pdk 0000000000000000000000000000000000000000
CASE_ENV=(KLT_V=0.9.3.dev1)
resolve_case "--klt-bin ignores a PATH klt off the pin" "=uvx --from klayout-tools==0.9.2 --with klayout==0.30.12 klt"
CASE_ENV=(KLT_V=0.9.2)
resolve_case "--klt-bin uses a PATH klt carrying the pin" "=klt"

# a cold-start .venv carrying the pin wins over both PATH forms (.venv is
# gitignored; the case is skipped when a real one exists). Its stub is the
# PATH stub with the version frozen at the pin, so the engine cases below can
# keep the PATH klt off-pin and still resolve to the .venv.
if [[ -x "$repo_root/.venv/bin/klt" ]]; then
  pass=$((pass + 1))
  echo "PASS: --klt-bin .venv case skipped (a real .venv/bin/klt exists)"
else
  mkdir -p "$repo_root/.venv/bin"
  sed 's/\${KLT_V:-0\.9\.2}/0.9.2/g' "$STUB_BIN/klt" >"$repo_root/.venv/bin/klt"
  chmod +x "$repo_root/.venv/bin/klt"
  CASE_ENV=(KLT_V=0.9.3.dev1)
  resolve_case "--klt-bin prefers .venv/bin/klt at the pin" "=$repo_root/.venv/bin/klt"
  # --check-flow then judges the engine that .venv loads (the first flow-smoke
  # record's shape: .venv klt 0.9.2 on klayout 0.30.13)
  fake_pdk f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
  MODE=(--check-flow)
  CASE_ENV=("${FLOW_OK[@]}" KLT_V=0.9.3.dev1 KLT_KLAYOUT_V=0.30.13)
  run_case 1 "--check-flow fails on a .venv klt at the pin whose klayout engine drifted"
  log_has "  ...resolved to the .venv, not the PATH klt" "^FAIL  klayout +.*loaded by .*\\.venv/bin/klt"
  CASE_ENV=("${FLOW_OK[@]}" KLT_V=0.9.3.dev1)
  run_case 0 "--check-flow passes on a .venv klt at the pin with the engine at the pin"
  log_has "  ...resolved to the .venv" "^ok    klayout +.*loaded by .*\\.venv/bin/klt"
  rm -rf "$repo_root/.venv"
fi

echo "----"
echo "test-setup-env: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
