"""Harness smoke test: reset the counter and check it increments.

Not a design claim -- it proves only that cocotb + Icarus run end to end in a
clean checkout, and that the run is recorded as evidence.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge


@cocotb.test()
async def counter_counts(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert int(dut.count.value) == 0, f"reset held but count={dut.count.value}"

    await RisingEdge(dut.clk)  # leave the read-only phase; reset still active on this edge
    dut.rst_n.value = 1        # release between edges
    await ReadOnly()
    assert int(dut.count.value) == 0, f"just released, no counting edge yet, count={dut.count.value}"

    for expected in range(1, 6):
        await RisingEdge(dut.clk)
        await ReadOnly()
        got = int(dut.count.value)
        assert got == expected, f"count={got}, expected {expected}"
