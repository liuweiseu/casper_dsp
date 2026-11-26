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
PARAMS = ['N_INPUTS', 'FFT_SIZE', 'INPUT_BIT_WIDTH', 'BIN_PT_IN', 'COEFF_BIT_WIDTH', 'ADD_LATENCY', 'MULT_LATENCY', 'BRAM_LATENCY', 'CONV_LATENCY', 'QUANTIZATION', 'OVERFLOW', 'DELAYS_BIT_LIMIT', 'MAX_FANOUT', 'BITGROWTH', 'MAX_BITS', 'HARDCODE_SHIFTS', 'SHIFT_SCHEDULE']
# sim_<name>.csv -> DUT port; LANE ports are arrays of N_INPUTS words
LANE_IN = ['pol1_re', 'pol1_im', 'pol2_re', 'pol2_im']
SCALAR_IN = ['sync', 'shift']
LANE_OUT = {'out1_re': 'out1_re', 'out1_im': 'out1_im', 'out2_re': 'out2_re', 'out2_im': 'out2_im'}
SCALAR_OUT = {'of': 'of', 'sync_out': 'sync_out'}

# casper async options: parameters (default when missing from params.json) and
# ports (driven / checked only when their sim_<name>.csv exists)
OPTION_DEFAULTS = {'ASYNC': 0}
OPTIONAL_IN = ['en']
OPTIONAL_OUT = {'dvalid': 'dvalid'}


def find_datadir(dut):
    """Return the simdataN directory whose integer parameters match the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS + list(OPTION_DEFAULTS)}
    for d in sorted(testdatadir.glob("simdata*")):
        p = dict(OPTION_DEFAULTS, **json.loads((d / "params.json").read_text()))
        if {k: p[k] for k in dut_params} == dut_params:
            return d, dut_params
    return None, dut_params


def load(datadir, name):
    """sim_<port>.csv, or sim_<port><j>.csv per element of a lane port, -> list of rows (each a list: N_INPUTS values for lane ports)."""
    return load_rows(datadir, name)


@cocotb.test()
async def module_test(dut):
    """Test biplex_core module.

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
    scalar_in = SCALAR_IN + [k for k in OPTIONAL_IN if (datadir / f"sim_{k}.csv").exists()]
    scalar_out = dict(SCALAR_OUT, **{k: v for k, v in OPTIONAL_OUT.items() if (datadir / f"sim_{k}.csv").exists()})
    stim = {k: load(datadir, k) for k in LANE_IN + scalar_in}
    expected = {k: load(datadir, k) for k in list(LANE_OUT) + list(scalar_out)}
    cycles = len(next(iter(expected.values())))
    cocotb.log.info(f"Loaded {cycles} cycles from {datadir.name}")

    for i in range(cycles):
        for k in LANE_IN:
            for n in range(lanes):
                getattr(dut, k)[n].value = stim[k][i][n]
        for k in scalar_in:
            getattr(dut, k).value = stim[k][i][0]
        await RisingEdge(dut.clk)
        for k, port in LANE_OUT.items():
            for n in range(lanes):
                actual = int(getattr(dut, port)[n].value)
                assert actual == expected[k][i][n], (
                    f"Index {i} lane {n}: expected {port}={expected[k][i][n]}, got {actual}"
                )
        for k, port in scalar_out.items():
            actual = int(getattr(dut, port).value)
            assert actual == expected[k][i][0], (
                f"Index {i}: expected {port}={expected[k][i][0]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {cycles} cycles verified")
