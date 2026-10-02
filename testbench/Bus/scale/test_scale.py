import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

PARAMS = ["N_BITS_IN", "BIN_PT_IN", "TYPE_IN", "SCALE_FACTOR", "N_BITS_OUT",
          "BIN_PT_OUT", "TYPE_OUT", "QUANTIZATION", "OVERFLOW", "LATENCY"]


def read_param(dut, name):
    """Read an integer parameter, keeping its sign (SCALE_FACTOR may be negative)."""
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
    """Test scale module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    sim_out.csv[i] = dout read after clock edge i (pre-edge read convention);
    the first LATENCY values are the zero power-on state of the pipeline.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    params = {name: read_param(dut, name) for name in PARAMS}
    cocotb.log.info(f"Testing with {params}")

    datadir = find_datadir(params)
    if datadir is None:
        cocotb.log.warning(f"No test data for {params}. Skipping.")
        return

    din = np.loadtxt(datadir / "sim_din.csv", dtype=int).tolist()
    expected = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i in range(len(expected)):
        dut.din.value = din[i]
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == expected[i], (
            f"Index {i}: din={din[i]} → expected dout={expected[i]}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
