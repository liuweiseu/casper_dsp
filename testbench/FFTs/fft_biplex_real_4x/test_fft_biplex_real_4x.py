import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json
import numpy as np

# test_data mirrors testbench/ at any depth: locate the testbench root
_here = Path(__file__).resolve().parent
_tb_root = next(p for p in _here.parents if p.name == "testbench")
testdatadir = _tb_root.parent / "test_data" / _here.relative_to(_tb_root)

# Integer parameters used to match the DUT against simdataN/params.json
PARAMS = ['N_BIPLEX_INPUTS', 'FFT_SIZE', 'INPUT_BIT_WIDTH', 'BIN_PT_IN', 'COEFF_BIT_WIDTH', 'ADD_LATENCY', 'MULT_LATENCY', 'BRAM_LATENCY', 'CONV_LATENCY', 'QUANTIZATION', 'OVERFLOW', 'DELAYS_BIT_LIMIT', 'COEFFS_BIT_LIMIT', 'MAX_FANOUT', 'BITGROWTH', 'MAX_BITS', 'HARDCODE_SHIFTS', 'SHIFT_SCHEDULE']
# sim_<name>.csv -> DUT port; LANE ports are arrays of 4·N_BIPLEX_INPUTS words
LANE_IN = ['pol_in']
SCALAR_IN = ['sync', 'shift']
LANE_OUT = {'pol_out_re': 'pol_out_re', 'pol_out_im': 'pol_out_im'}
SCALAR_OUT = {'sync_out': 'sync_out', 'of': 'of'}


def find_datadir(dut):
    """Return the simdataN directory whose integer parameters match the DUT."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS}
    for d in sorted(testdatadir.glob("simdata*")):
        p = json.loads((d / "params.json").read_text())
        if {k: p[k] for k in PARAMS} == dut_params:
            return d, dut_params
    return None, dut_params


def load(datadir, name):
    """CSV -> list of rows (each a list: one value per element for lane ports)."""
    return np.loadtxt(datadir / f"sim_{name}.csv", dtype=int, ndmin=2).tolist()


@cocotb.test()
async def module_test(dut):
    """Test fft_biplex_real_4x module.

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

    lanes = 4 * int(dut.N_BIPLEX_INPUTS.value)
    lanes_out = lanes
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
            for n in range(lanes_out):
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
