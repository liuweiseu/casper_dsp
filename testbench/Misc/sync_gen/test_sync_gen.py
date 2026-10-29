import json

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from testbench.data_paths import module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

INT_PARAMS = ["SIM_ACC_LEN", "FFT_SIZE", "FFT_SIMULT_INPUTS", "PFB_FIR_TAPS", "SCALE"]
INPUTS = ["sync", "sync_period_sel", "sync_period_var"]


def pack(values):
    """mask vector -> packed parameter value (32-bit elements, first in the MSBs)"""
    v = 0
    for x in values:
        v = (v << 32) | (x & 0xFFFFFFFF)
    return v


def load(path):
    return [int(v) for v in path.read_text().split()]


@cocotb.test()
async def module_test(dut):
    """Test sync_gen: the swreg values drive the ports, sync_out against the Simulink export."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut_params = {p: int(getattr(dut, p).value) for p in INT_PARAMS}
    dut_params["REORDER_VEC"] = int(dut.REORDER_VEC.value)
    datadir = None
    for d in sorted(testdatadir.glob("simdata*")):
        p = json.loads((d / "params.json").read_text())
        if dict({k: p[k] for k in INT_PARAMS}, REORDER_VEC=pack(p["REORDER_VEC"])) == dut_params:
            datadir = d
            break
    assert datadir is not None, f"no simdataN/params.json in {testdatadir} matches {dut_params}"
    cocotb.log.info(f"Testing {datadir.name}: {dut_params}")

    stim = {k: load(datadir / f"sim_{k}.csv") for k in INPUTS}
    expected = load(datadir / "sim_sync_out.csv")
    for i in range(len(expected)):
        for k in INPUTS:
            getattr(dut, k).value = stim[k][i]
        await RisingEdge(dut.clk)
        actual = int(dut.sync_out.value)
        assert actual == expected[i], (f"Index {i}: " + ", ".join(f"{k}={stim[k][i]:#x}" for k in INPUTS)
                                       + f" -> expected sync_out={expected[i]}, got {actual}")

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles")
