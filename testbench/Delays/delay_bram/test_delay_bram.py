import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

# Integer parameters used to match the DUT against simdataN/params.json
PARAMS = ['BITWIDTH', 'DELAY_LEN']
# CSV name (sim_<name>.csv) -> DUT port
INPUTS = {'din': 'din'}
OUTPUTS = {'dout': 'dout'}


def find_datadir(dut):
    """Return the simdataN directory whose integer parameters match the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS}
    for d in sorted(testdatadir.glob("simdata*")):
        p = json.loads((d / "params.json").read_text())
        if {k: p[k] for k in PARAMS} == dut_params:
            return d, dut_params
    return None, dut_params


@cocotb.test()
async def module_test(dut):
    """Test delay_bram module (PLATFORM = "GENERIC").

    Each simdataN/params.json holds one parameter set (see test_data.md).
    sim_<output>.csv[i] = output read after clock edge i (pre-edge read
    convention), so the first latency values are the zero power-on state.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    datadir, dut_params = find_datadir(dut)
    cocotb.log.info(f"Testing with {dut_params}")
    if datadir is None:
        cocotb.log.warning(f"No test data for {dut_params}. Skipping.")
        return

    stim = {k: np.loadtxt(datadir / f"sim_{k}.csv", dtype=int).tolist() for k in INPUTS}
    expected = {k: np.loadtxt(datadir / f"sim_{k}.csv", dtype=int).tolist() for k in OUTPUTS}
    cycles = len(next(iter(expected.values())))
    cocotb.log.info(f"Loaded {cycles} cycles from {datadir.name}")

    for i in range(cycles):
        for k, port in INPUTS.items():
            getattr(dut, port).value = stim[k][i]
        await RisingEdge(dut.clk)
        for k, port in OUTPUTS.items():
            actual = int(getattr(dut, port).value)
            assert actual == expected[k][i], (
                f"Index {i}: inputs={ {k: stim[k][i] for k in INPUTS} } "
                f"→ expected {port}={expected[k][i]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
