import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import numpy as np

# testdir is used for getting the path for the input and output data file
testdir = Path(__file__).resolve().parent


@cocotb.test()
async def module_test(dut):
    """Test register module.

    Drives d, en, and rst before each rising edge and compares q against
    the expected value in sim_out.csv after the edge.

    The test covers four behaviours:
      - Reset      : rst=1 forces q to zero regardless of d/en.
      - Enable      : en=1, rst=0 latches d into q on the rising edge.
      - Hold       : en=0, rst=0 leaves q unchanged.
      - Priority   : rst takes precedence over en when both are asserted.

    Parameter set: BITWIDTH=4
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    bitwidth = int(dut.BITWIDTH.value)
    cocotb.log.info(f"Testing with BITWIDTH={bitwidth}")

    sim_d    = np.loadtxt(testdir / "sim_d.csv",   dtype=int).tolist()
    sim_en   = np.loadtxt(testdir / "sim_en.csv",  dtype=int).tolist()
    sim_rst  = np.loadtxt(testdir / "sim_rst.csv", dtype=int).tolist()
    expected = np.loadtxt(testdir / "sim_out.csv", dtype=int).tolist()

    for i, (d_val, en_val, rst_val, exp) in enumerate(
        zip(sim_d, sim_en, sim_rst, expected)
    ):
        dut.d.value   = d_val
        dut.en.value  = en_val
        dut.rst.value = rst_val
        await RisingEdge(dut.clk)
        actual = int(dut.q.value)
        assert actual == exp, (
            f"Index {i}: d={d_val}, en={en_val}, rst={rst_val} "
            f"→ expected q={exp}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_d)} cycles verified")
