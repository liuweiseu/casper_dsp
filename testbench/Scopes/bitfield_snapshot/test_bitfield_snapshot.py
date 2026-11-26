import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from testbench.data_paths import find_data_dir, module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

PARAMS = ["IO_WIDTH", "SNAP_NSAMPLES", "SNAP_DATA_WIDTH", "SNAP_DELAY"]
INPUTS = ["din", "we", "trig", "ctrl"]
OUTPUTS = ["status", "bram_addr", "bram_data_in", "bram_we", "arm_out"]


def load(path):
    # din / bram_data_in can be 128 bits wide: parse as Python ints
    return [int(v) for v in path.read_text().split()]


@cocotb.test()
async def module_test(dut):
    """Test bitfield_snapshot against the Simulink export.

    Drives din / we / trig and the ctrl swreg value; checks the status swreg
    value, the shared_bram inputs and arm_out every cycle.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    datadir = find_data_dir(dut, testdatadir, PARAMS)
    cocotb.log.info(f"Testing {datadir.name}: " + ", ".join(f"{p}={int(getattr(dut, p).value)}" for p in PARAMS))
    stim = {k: load(datadir / f"sim_{k}.csv") for k in INPUTS}
    expected = {k: load(datadir / f"sim_{k}.csv") for k in OUTPUTS}
    dut.bram_data_out.value = 0

    n = len(stim["din"])
    for i in range(n):
        for k in INPUTS:
            getattr(dut, k).value = stim[k][i]
        await RisingEdge(dut.clk)
        for k in OUTPUTS:
            actual = int(getattr(dut, k).value)
            assert actual == expected[k][i], (f"Index {i}: " + ", ".join(f"{p}={stim[p][i]:#x}" for p in INPUTS)
                                              + f" -> expected {k}={expected[k][i]:#x}, got {actual:#x}")

    cocotb.log.info(f"module_test PASSED — {n} cycles")
