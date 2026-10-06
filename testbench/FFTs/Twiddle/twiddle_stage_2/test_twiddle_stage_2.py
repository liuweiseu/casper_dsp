import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json
import numpy as np

from testbench.csv_ports import load_rows

# test_data mirrors testbench/ at any depth (this module is in a nested
# category, testbench/FFTs/Twiddle/<module>/), so locate the testbench root
# instead of assuming a single category level
_here = Path(__file__).resolve().parent
_tb_root = next(p for p in _here.parents if p.name == "testbench")
testdatadir = _tb_root.parent / "test_data" / _here.relative_to(_tb_root)

# Integer parameters used to match the DUT against simdataN/params.json
PARAMS = ['N_INPUTS', 'FFT_SIZE', 'INPUT_BIT_WIDTH', 'BIN_PT_IN', 'ADD_LATENCY', 'MULT_LATENCY', 'BRAM_LATENCY', 'CONV_LATENCY']
LANE_IN = ["ai_re", "ai_im", "bi_re", "bi_im"]
LANE_OUT = ["ao_re", "ao_im", "bwo_re", "bwo_im"]


def find_datadir(dut):
    """Return the simdataN directory whose integer parameters match the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS}
    for d in sorted(testdatadir.glob("simdata*")):
        p = json.loads((d / "params.json").read_text())
        if {k: p[k] for k in PARAMS} == dut_params:
            return d, dut_params
    return None, dut_params


def load(datadir, port):
    """sim_<port>.csv, or sim_<port><j>.csv per element of a lane port, -> list of rows; lane ports give one list of N_INPUTS values per row."""
    return load_rows(datadir, port)


@cocotb.test()
async def module_test(dut):
    """Test twiddle_stage_2 module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    Row i of sim_<output>.csv = output read after clock edge i (pre-edge read
    convention), so the first latency rows are the zero power-on state.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    datadir, dut_params = find_datadir(dut)
    cocotb.log.info(f"Testing with {dut_params}")
    if datadir is None:
        cocotb.log.warning(f"No test data for {dut_params}. Skipping.")
        return

    lanes = int(dut.N_INPUTS.value)
    stim = {p: load(datadir, p) for p in LANE_IN + ["sync_in"]}
    expected = {p: load(datadir, p) for p in LANE_OUT + ["sync_out"]}
    cycles = len(expected["sync_out"])
    cocotb.log.info(f"Loaded {cycles} cycles × {lanes} lanes from {datadir.name}")

    for i in range(cycles):
        for p in LANE_IN:
            for k in range(lanes):
                getattr(dut, p)[k].value = stim[p][i][k]
        dut.sync_in.value = stim["sync_in"][i][0]
        await RisingEdge(dut.clk)
        for p in LANE_OUT:
            for k in range(lanes):
                actual = int(getattr(dut, p)[k].value)
                assert actual == expected[p][i][k], (
                    f"Index {i} lane {k}: expected {p}={expected[p][i][k]}, got {actual}"
                )
        actual = int(dut.sync_out.value)
        assert actual == expected["sync_out"][i][0], (
            f"Index {i}: expected sync_out={expected['sync_out'][i][0]}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
