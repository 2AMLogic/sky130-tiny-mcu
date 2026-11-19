# Shared cocotb/Icarus rules, driven by verification/Makefile (not run directly).
# Copied by pattern from sky130-riscv-soc's verification/cocotb.mk (source
# commit in verification/README.md), cut down to the per-testbench PYTHONPATH
# this block needs -- no shared bench lib yet.
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
COCOTB_RESULTS_FILE ?= $(SIM_BUILD)/results.xml
export PYTHONPATH := $(TESTDIR):$(PYTHONPATH)
include $(shell cocotb-config --makefiles)/Makefile.sim
