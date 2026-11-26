import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import numpy as np
from testbench.data_paths import find_data_dir, module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

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
    edge_type  = int(dut.EDGE.value)
    output_pol = int(dut.POLARITY.value)
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
        simdata0 : EDGE=0(rising),  POLARITY=0(active_high)
        simdata1 : EDGE=0(rising),  POLARITY=1(active_low)
        simdata2 : EDGE=1(falling), POLARITY=0(active_high)
        simdata3 : EDGE=1(falling), POLARITY=1(active_low)
        simdata4 : EDGE=2(both),    POLARITY=0(active_high)
        simdata5 : EDGE=2(both),    POLARITY=1(active_low)
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    edge_type  = int(dut.EDGE.value)
    output_pol = int(dut.POLARITY.value)
    cocotb.log.info(f"Testing with EDGE={edge_type}, POLARITY={output_pol}")

    datadir = find_data_dir(dut, testdatadir, ["EDGE", "POLARITY"])

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
