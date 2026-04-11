import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import numpy as np

# testdatadir points to the corresponding test_data subdirectory
_tb = Path(__file__).resolve().parent
testdatadir = _tb.parents[2] / "test_data" / _tb.parent.name / _tb.name

# Must match localparam values in edge_detect.v
RISING  = 0
FALLING = 1
ACTIVE_HIGH = 0
ACTIVE_LOW  = 1


@cocotb.test()
async def module_test(dut):
    """Test edge_detect module.

    For each value in sim_in.csv, drive din before the rising edge and
    compare dout against the expected value in sim_out.csv after the edge.

    Parameter sets:
        simdata0 : EDGE_TYPE=0(rising),  OUTPUT_POL=0(active_high)
        simdata1 : EDGE_TYPE=0(rising),  OUTPUT_POL=1(active_low)
        simdata2 : EDGE_TYPE=1(falling), OUTPUT_POL=0(active_high)
        simdata3 : EDGE_TYPE=1(falling), OUTPUT_POL=1(active_low)
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    edge_type  = int(dut.EDGE_TYPE.value)
    output_pol = int(dut.OUTPUT_POL.value)
    cocotb.log.info(f"Testing with EDGE_TYPE={edge_type}, OUTPUT_POL={output_pol}")

    if   edge_type == RISING  and output_pol == ACTIVE_HIGH:
        datadir = testdatadir / "simdata0"
    elif edge_type == RISING  and output_pol == ACTIVE_LOW:
        datadir = testdatadir / "simdata1"
    elif edge_type == FALLING and output_pol == ACTIVE_HIGH:
        datadir = testdatadir / "simdata2"
    elif edge_type == FALLING and output_pol == ACTIVE_LOW:
        datadir = testdatadir / "simdata3"
    else:
        cocotb.log.warning(
            f"No test data for EDGE_TYPE={edge_type}, OUTPUT_POL={output_pol}. Skipping."
        )
        return

    sim_in           = np.loadtxt(datadir / "sim_in.csv",  dtype=int).tolist()
    expected_results = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(sim_in)} values from {datadir.name}/")

    for i, (din_val, expected) in enumerate(zip(sim_in, expected_results)):
        dut.din.value = din_val
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == expected, (
            f"Index {i}: din={din_val}, "
            f"expected dout={expected}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_in)} cycles verified")
