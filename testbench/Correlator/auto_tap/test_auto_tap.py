import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json

# test_data mirrors testbench/ at any depth: locate the testbench root
_here = Path(__file__).resolve().parent
_tb_root = next(p for p in _here.parents if p.name == "testbench")
testdatadir = _tb_root.parent / "test_data" / _here.relative_to(_tb_root)

# Integer parameters matched against simdataN/params.json
PARAMS = ['N_ANTS', 'N_SIMULTAN', 'N_BITS', 'ACC_LEN', 'ADD_LATENCY', 'MULT_LATENCY', 'BRAM_LATENCY', 'MULT_TYPE', 'USE_BRAM_DELAY']
# sim_<name>.csv -> DUT port of the same name
INPUTS = ['a_del', 'a_ndel', 'a_loop', 'acc_in', 'valid_in', 'sync_in']
OUTPUTS = ['a_del_out', 'a_ndel_out', 'a_end_out', 'acc_out', 'valid_out', 'rst_out', 'sync_out']


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
    """Test auto_tap module.

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

    stim = {k: load(datadir / f"sim_{k}.csv") for k in INPUTS}
    expected = {k: load(datadir / f"sim_{k}.csv") for k in OUTPUTS}
    cycles = len(next(iter(expected.values())))
    cocotb.log.info(f"Loaded {cycles} cycles from {datadir.name}")

    for i in range(cycles):
        for k in INPUTS:
            getattr(dut, k).value = stim[k][i]
        await RisingEdge(dut.clk)
        for k in OUTPUTS:
            actual = int(getattr(dut, k).value)
            assert actual == expected[k][i], (
                f"Index {i}: expected {k}={expected[k][i]:#x}, got {actual:#x}"
            )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
