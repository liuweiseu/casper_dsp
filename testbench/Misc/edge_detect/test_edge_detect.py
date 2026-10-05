import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

# testdatadir points to the corresponding test_data subdirectory
_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

# Must match localparam values in edge_detect.v
RISING  = 0
FALLING = 1
BOTH    = 2
ACTIVE_HIGH = 0
ACTIVE_LOW  = 1


@cocotb.test()
async def power_on_test(dut):
    """din_prev powers on at 0 (as in Simulink).

    Runs first, before any clock edge: dout is combinational in din and
    din_prev, so with din=1 it shows din_prev's initial value. din is set
    back to 0 so module_test starts from the power-on state.
    """
    edge_type  = int(dut.EDGE_TYPE.value)
    output_pol = int(dut.OUTPUT_POL.value)
    # din=1, din_prev=0: a rising edge (and any edge), no falling edge
    detect = 0 if edge_type == FALLING else 1
    expected = detect ^ output_pol

    dut.clk.value = 0
    dut.din.value = 1
    await Timer(1, units="ns")
    actual = dut.dout.value
    assert actual.is_resolvable and int(actual) == expected, (
        f"Power-on: din=1, expected dout={expected}, got {actual}"
    )
    dut.din.value = 0
    await Timer(1, units="ns")


@cocotb.test()
async def module_test(dut):
    """Test edge_detect module.

    For each value in sim_din.csv, drive din before the rising edge and
    compare dout against the expected value in sim_dout.csv after the edge.

    Parameter sets:
        simdata0 : EDGE_TYPE=0(rising),  OUTPUT_POL=0(active_high)
        simdata1 : EDGE_TYPE=0(rising),  OUTPUT_POL=1(active_low)
        simdata2 : EDGE_TYPE=1(falling), OUTPUT_POL=0(active_high)
        simdata3 : EDGE_TYPE=1(falling), OUTPUT_POL=1(active_low)
        simdata4 : EDGE_TYPE=2(both),    OUTPUT_POL=0(active_high)
        simdata5 : EDGE_TYPE=2(both),    OUTPUT_POL=1(active_low)
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
    elif edge_type == BOTH    and output_pol == ACTIVE_HIGH:
        datadir = testdatadir / "simdata4"
    elif edge_type == BOTH    and output_pol == ACTIVE_LOW:
        datadir = testdatadir / "simdata5"
    else:
        cocotb.log.warning(
            f"No test data for EDGE_TYPE={edge_type}, OUTPUT_POL={output_pol}. Skipping."
        )
        return

    sim_in           = np.loadtxt(datadir / "sim_din.csv",  dtype=int).tolist()
    expected_results = np.loadtxt(datadir / "sim_dout.csv", dtype=int).tolist()
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
