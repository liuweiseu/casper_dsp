import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import json
from testbench.data_paths import module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

# Integer parameters matched against simdataN/params.json
PARAMS = ['N_ANTS', 'N_BITS', 'ACC_LEN', 'DEMUX_FACTOR', 'ADD_LATENCY', 'MULT_LATENCY', 'BRAM_LATENCY', 'USE_DED_MULT', 'USE_BRAM_DELAY', 'MCNT_BITS']
# sim_<name>.csv -> DUT port of the same name
INPUTS = ['sync_in', 'ant', 'window_valid', 'mcnt_in']
OUTPUTS = ['sync_out', 'acc', 'valid', 'mcnt_out']


def find_datadir(dut):
    """Return the simdataN directory whose params.json matches the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS}
    for d in sorted(testdatadir.glob("simdata*")):
        if json.loads((d / "params.json").read_text()) == dut_params:
            return d, dut_params
    return None, dut_params


def load(path):
    """CSV of raw words -> Python ints (words may exceed 64 bits)."""
    return [int(x) for x in path.read_text().split()]


@cocotb.test()
async def module_test(dut):
    """Test xeng module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    Row i of a CSV is the value driven before / read after clock edge i
    (pre-edge read convention).

    Besides the outputs, the antenna loop is checked inside the RTL: the
    auto_tap's a_end_out must equal ant delayed by exactly N_ANTS*ACC_LEN
    cycles (0 before that).
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    datadir, dut_params = find_datadir(dut)
    cocotb.log.info(f"Testing with {dut_params}")
    if datadir is None:
        cocotb.log.warning(f"No test data for {dut_params}. Skipping.")
        return

    stim = {k: load(datadir / f"sim_{k}.csv") for k in INPUTS}
    expected = {k: load(datadir / f"sim_{k}.csv") for k in OUTPUTS}
    cycles = len(next(iter(expected.values())))
    cocotb.log.info(f"Loaded {cycles} cycles from {datadir.name}")

    lag = dut_params["N_ANTS"] * dut_params["ACC_LEN"]
    a_end = dut.u_auto_tap.a_end_out

    for i in range(cycles):
        for k in INPUTS:
            getattr(dut, k).value = stim[k][i]
        await RisingEdge(dut.clk)
        want = stim["ant"][i - lag] if i >= lag else 0
        assert int(a_end.value) == want, (
            f"Index {i}: auto_tap.a_end_out={int(a_end.value):#x}, expected ant[{i - lag}]={want:#x}"
        )
        for k in OUTPUTS:
            actual = int(getattr(dut, k).value)
            assert actual == expected[k][i], (
                f"Index {i}: expected {k}={expected[k][i]:#x}, got {actual:#x}"
            )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
