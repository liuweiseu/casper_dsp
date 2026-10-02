import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

PARAMS = ["N_BITS_A", "BIN_PT_A", "TYPE_A", "N_BITS_B", "BIN_PT_B", "TYPE_B",
          "N_BITS_OUT", "BIN_PT_OUT", "TYPE_OUT", "QUANTIZATION", "OVERFLOW",
          "MULT_SPEC", "MULT_LATENCY", "ADD_LATENCY"]


def read_param(dut, name):
    """Read an integer parameter, keeping its sign (parameters are declared as signed int)."""
    v = getattr(dut, name).value
    return v.to_signed() if hasattr(v, "to_signed") else int(v)


def find_datadir(params):
    """Return the simdataN directory whose params.json matches the DUT."""
    for d in sorted(testdatadir.glob("simdata*")):
        if json.loads((d / "params.json").read_text()) == params:
            return d
    return None


@cocotb.test()
async def module_test(dut):
    """Test complex_multiplier module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    sim_out_re/im.csv[i] = dout_re/im read after clock edge i (pre-edge read
    convention); the first LATENCY values (MULT_LATENCY + ADD_LATENCY for
    MULT_SPEC=0, MULT_LATENCY + 2*ADD_LATENCY for MULT_SPEC=1) are the zero
    power-on state of the pipeline.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    params = {name: read_param(dut, name) for name in PARAMS}
    cocotb.log.info(f"Testing with {params}")

    datadir = find_datadir(params)
    if datadir is None:
        cocotb.log.warning(f"No test data for {params}. Skipping.")
        return

    ports = ["a_re", "a_im", "b_re", "b_im"]
    stim = {p: np.loadtxt(datadir / f"sim_{p}.csv", dtype=int).tolist() for p in ports}
    exp_re = np.loadtxt(datadir / "sim_out_re.csv", dtype=int).tolist()
    exp_im = np.loadtxt(datadir / "sim_out_im.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(exp_re)} expected values from {datadir.name}")

    for i in range(len(exp_re)):
        for p in ports:
            getattr(dut, p).value = stim[p][i]
        await RisingEdge(dut.clk)
        actual_re = int(dut.dout_re.value)
        actual_im = int(dut.dout_im.value)
        inputs = {p: stim[p][i] for p in ports}
        assert (actual_re, actual_im) == (exp_re[i], exp_im[i]), (
            f"Index {i}: {inputs} → expected (re, im)=({exp_re[i]}, {exp_im[i]}), "
            f"got ({actual_re}, {actual_im})"
        )

    cocotb.log.info(f"module_test PASSED — {len(exp_re)} cycles verified")
