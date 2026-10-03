import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

# Integer parameters matched against simdataN/params.json
PARAMS = ['DELAY']
# sim_<name>.csv -> DUT port
INPUTS = ['din']
OUTPUTS = ['dout']


def find_datadir(dut):
    """Return the simdataN directory whose params.json matches the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS}
    for d in sorted(testdatadir.glob("simdata*")):
        if json.loads((d / "params.json").read_text()) == dut_params:
            return d, dut_params
    return None, dut_params


@cocotb.test()
async def module_test(dut):
    """Test window_delay module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    Row i of a CSV is the value driven before / read after clock edge i
    (pre-edge read convention).
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    datadir, dut_params = find_datadir(dut)
    cocotb.log.info(f"Testing with {dut_params}")
    if datadir is None:
        cocotb.log.warning(f"No test data for {dut_params}. Skipping.")
        return

    stim = {k: np.loadtxt(datadir / f"sim_{k}.csv", dtype=np.int64).tolist() for k in INPUTS}
    expected = {k: np.loadtxt(datadir / f"sim_{k}.csv", dtype=np.int64).tolist() for k in OUTPUTS}
    cycles = len(next(iter(expected.values())))
    cocotb.log.info(f"Loaded {cycles} cycles from {datadir.name}")

    for i in range(cycles):
        for k in INPUTS:
            getattr(dut, k).value = stim[k][i]
        await RisingEdge(dut.clk)
        for k in OUTPUTS:
            actual = int(getattr(dut, k).value)
            assert actual == expected[k][i], (
                f"Index {i}: inputs {({k2: stim[k2][i] for k2 in INPUTS})}, "
                f"expected {k}={expected[k][i]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
