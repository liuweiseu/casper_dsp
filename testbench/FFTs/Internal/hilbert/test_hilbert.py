import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import json
import numpy as np

from testbench.csv_ports import load_rows
from testbench.data_paths import module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

# Integer parameters used to match the DUT against simdataN/params.json
PARAMS = ['N_INPUTS', 'BIT_WIDTH', 'BIN_PT_IN', 'ADD_LATENCY', 'CONV_LATENCY']
# casper misc pass-through: in params.json only for sets with MISC = 1
MISC_DEFAULTS = {'MISC': 0, 'MISC_WIDTH': 1}
# sim_<name>.csv -> DUT port; LANE ports are arrays of N_INPUTS words
LANE_IN = ['a_re', 'a_im', 'b_re', 'b_im']
SCALAR_IN = ['misci']                    # MISC = 1 sets only
LANE_OUT = {'even_re': 'even_re', 'even_im': 'even_im', 'odd_re': 'odd_re', 'odd_im': 'odd_im'}
SCALAR_OUT = {'misco': 'misco'}          # MISC = 1 sets only


def find_datadir(dut):
    """Return the simdataN directory whose integer parameters match the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in list(PARAMS) + list(MISC_DEFAULTS)}
    for d in sorted(testdatadir.glob("simdata*")):
        p = dict(MISC_DEFAULTS, **json.loads((d / "params.json").read_text()))
        if {k: p[k] for k in dut_params} == dut_params:
            return d, dut_params
    return None, dut_params


def load(datadir, name):
    """sim_<port>.csv, or sim_<port><j>.csv per element of a lane port, -> list of rows (each a list: N_INPUTS values for lane ports)."""
    return load_rows(datadir, name)


@cocotb.test()
async def module_test(dut):
    """Test hilbert module.

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

    lanes = int(dut.N_INPUTS.value)
    misc = [] if dut_params['MISC'] == 0 else ['misci', 'misco']
    stim = {k: load(datadir, k) for k in LANE_IN + SCALAR_IN if k in LANE_IN or k in misc}
    expected = {k: load(datadir, k) for k in list(LANE_OUT) + list(SCALAR_OUT) if k in LANE_OUT or k in misc}
    cycles = len(next(iter(expected.values())))
    cocotb.log.info(f"Loaded {cycles} cycles from {datadir.name}")

    for i in range(cycles):
        for k in LANE_IN:
            for n in range(lanes):
                getattr(dut, k)[n].value = stim[k][i][n]
        for k in SCALAR_IN:
            if k in stim:
                getattr(dut, k).value = stim[k][i][0]
        await RisingEdge(dut.clk)
        for k, port in LANE_OUT.items():
            for n in range(lanes):
                actual = int(getattr(dut, port)[n].value)
                assert actual == expected[k][i][n], (
                    f"Index {i} lane {n}: expected {port}={expected[k][i][n]}, got {actual}"
                )
        for k, port in SCALAR_OUT.items():
            if k not in expected:
                continue
            actual = int(getattr(dut, port).value)
            assert actual == expected[k][i][0], (
                f"Index {i}: expected {port}={expected[k][i][0]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
