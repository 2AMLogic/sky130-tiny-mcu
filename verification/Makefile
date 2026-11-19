# Single runner entry point for the cocotb + Icarus harness.
#
#   make -C verification smoke   harness smoke test on tests/smoke/ (a trivial
#                                counter DUT, not design RTL), recorded under
#                                records/smoke/
#
# Copied by pattern from sky130-riscv-soc's verification/Makefile (source
# commit in verification/README.md), cut down to the single target this block
# needs while it has no design RTL yet. A new test directory under
# tests/<name>/ adds a target the same way.
# Needs cocotb (pinned in ../scripts/setup-env.sh) and iverilog on PATH.
# Fails, rather than skips, when either is missing.

SIM ?= icarus
export PYTHON_BIN ?= python3
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

# Guards, stated once and used as a recipe line: every cocotb target starts
# with $(CHECK_COCOTB) and $(CHECK_IVERILOG). Fail, not skip.
define CHECK_COCOTB
@$(PYTHON_BIN) -c 'import cocotb' || { echo "cocotb not importable: see verification/README.md" >&2; exit 1; }
endef

define CHECK_IVERILOG
@command -v iverilog >/dev/null || { echo "iverilog not on PATH: see verification/README.md" >&2; exit 1; }
endef

SMOKE_BUILD := $(ROOT)/sim_build/smoke
SMOKE_LOG := $(SMOKE_BUILD)/smoke.log

.PHONY: smoke
smoke:
	$(CHECK_COCOTB)
	$(CHECK_IVERILOG)
	@mkdir -p $(SMOKE_BUILD)
	$(MAKE) -f $(ROOT)/cocotb.mk \
	    TESTDIR=$(ROOT)/tests/smoke TOPLEVEL=smoke MODULE=test_smoke \
	    VERILOG_SOURCES=$(ROOT)/tests/smoke/smoke.v \
	    COCOTB_RESULTS_FILE=$(SMOKE_BUILD)/results.xml \
	    SIM_BUILD=$(SMOKE_BUILD) >$(SMOKE_LOG) 2>&1 \
	    || { tail -40 $(SMOKE_LOG) >&2; exit 1; }
	@set -e; \
	ts=$$(date -u +%Y%m%dT%H%M%SZ); sha=$$(git rev-parse HEAD); \
	while [ -e $(ROOT)/records/smoke/$${ts}-$${sha} ]; do sleep 1; ts=$$(date -u +%Y%m%dT%H%M%SZ); done; \
	rec=$(ROOT)/records/smoke/$${ts}-$${sha}; mkdir -p $$rec; \
	cp $(SMOKE_LOG) $$rec/smoke.log.txt; \
	cp $(SMOKE_BUILD)/results.xml $$rec/results.xml; \
	cocotb_run=$$($(PYTHON_BIN) -c 'import cocotb;print(cocotb.__version__)' 2>/dev/null) \
	    || { echo "cannot probe the running cocotb version: not recording" >&2; exit 1; }; \
	iverilog_run=$$(iverilog -V 2>/dev/null | sed -n 's/^Icarus Verilog version \([^ ]*\) .*/\1/p'); \
	[ -n "$$iverilog_run" ] || { echo "cannot probe the running iverilog version: not recording" >&2; exit 1; }; \
	$(PYTHON_BIN) -c 'import json,sys; rec,sha,coc,iv=sys.argv[1:]; json.dump({"commit":sha,"pdk_revision":"n/a, no PDK used (RTL simulation only)","tool_versions":{"cocotb":coc,"iverilog":iv},"command":"make -C verification smoke"}, open(rec+"/provenance.json","w"), indent=2); print("record:", rec)' $$rec "$$sha" "$$cocotb_run" "$$iverilog_run"; \
	echo "smoke: PASS (record $$rec)"
