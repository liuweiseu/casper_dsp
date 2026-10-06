import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json
import numpy as np

from testbench.csv_ports import load_rows

# test_data mirrors testbench/ at any depth: locate the testbench root
_here = Path(__file__).resolve().parent
_tb_root = next(p for p in _here.parents if p.name == "testbench")
testdatadir = _tb_root.parent / "test_data" / _here.relative_to(_tb_root)

# Integer parameters used to match the DUT against simdataN/params.json
PARAMS = ['N_BITS_IN', 'BIN_PT_IN', 'N_BITS_OUT', 'BIN_PT_OUT', 'QUANTIZATION', 'OVERFLOW', 'LATENCY']
# sim_<name>.csv -> DUT port; LANE ports are arrays of N_INPUTS words
LANE_IN = []
SCALAR_IN = ['din']
LANE_OUT = {}
SCALAR_OUT = {'dout': 'dout', 'of': 'of'}


def find_datadir(dut):
    """Return the simdataN directory whose integer parameters match the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS}
    for d in sorted(testdatadir.glob("simdata*")):
        p = json.loads((d / "params.json").read_text())
        if {k: p[k] for k in PARAMS} == dut_params:
            return d, dut_params
    return None, dut_params


def load(datadir, name):
    """sim_<port>.csv, or sim_<port><j>.csv per element of a lane port, -> list of rows (each a list: N_INPUTS values for lane ports)."""
    return load_rows(datadir, name)


@cocotb.test()
async def module_test(dut):
    """Test convert_of module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    Row i of an output CSV = value read after clock edge i (pre-edge read
    convention), so the first latency rows are the zero power-on state.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    datadir, dut_params = find_datadir(dut)
    cocotb.log.info(f"Testing with {dut_params}")
    if datadir is None:
        cocotb.log.warning(f"No test data for {dut_params}. Skipping.")
        return

    lanes = int(dut.N_INPUTS.value) if LANE_IN else 1
    stim = {k: load(datadir, k) for k in LANE_IN + SCALAR_IN}
    expected = {k: load(datadir, k) for k in list(LANE_OUT) + list(SCALAR_OUT)}
    cycles = len(next(iter(expected.values())))
    cocotb.log.info(f"Loaded {cycles} cycles from {datadir.name}")

    for i in range(cycles):
        for k in LANE_IN:
            for n in range(lanes):
                getattr(dut, k)[n].value = stim[k][i][n]
        for k in SCALAR_IN:
            getattr(dut, k).value = stim[k][i][0]
        await RisingEdge(dut.clk)
        for k, port in LANE_OUT.items():
            for n in range(lanes):
                actual = int(getattr(dut, port)[n].value)
                assert actual == expected[k][i][n], (
                    f"Index {i} lane {n}: expected {port}={expected[k][i][n]}, got {actual}"
                )
        for k, port in SCALAR_OUT.items():
            actual = int(getattr(dut, port).value)
            assert actual == expected[k][i][0], (
                f"Index {i}: expected {port}={expected[k][i][0]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
