import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import json
import numpy as np
from testbench.data_paths import module_data_dir

testdatadir = module_data_dir(__file__)

PARAMS = ["N_BITS_IN", "BIN_PT_IN", "TYPE_IN", "N_BITS_OUT", "BIN_PT_OUT",
          "TYPE_OUT", "QUANTIZATION", "OVERFLOW", "CSP_LATENCY"]

# casper misc pass-through: in params.json only for sets with MISC = 1
MISC_PARAMS = ["MISC", "MISC_WIDTH"]
# casper of = on: overflow output; in params.json only for sets with OF = 1


def read_param(dut, name):
    """Read an integer parameter, keeping its sign (BIN_PT_IN may be negative)."""
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
    """Test convert module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    sim_dout.csv[i] = dout read after clock edge i (pre-edge read convention);
    the first CSP_LATENCY values are the zero power-on state of the pipeline.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    params = {name: read_param(dut, name) for name in PARAMS}
    if read_param(dut, "MISC"):
        params.update({name: read_param(dut, name) for name in MISC_PARAMS})
    if read_param(dut, "OF"):
        params["OF"] = read_param(dut, "OF")
    cocotb.log.info(f"Testing with {params}")

    datadir = find_datadir(params)
    if datadir is None:
        cocotb.log.warning(f"No test data for {params}. Skipping.")
        return

    din = np.loadtxt(datadir / "sim_din.csv", dtype=int).tolist()
    expected = np.loadtxt(datadir / "sim_dout.csv", dtype=int).tolist()
    of = params.get("OF", 0)
    if of:
        overflow = np.loadtxt(datadir / "sim_overflow.csv", dtype=int).tolist()
    misc = params.get("MISC", 0)
    if misc:
        misci = np.loadtxt(datadir / "sim_misci.csv", dtype=int).tolist()
        misco = np.loadtxt(datadir / "sim_misco.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i in range(len(expected)):
        dut.din.value = din[i]
        if misc:
            dut.misci.value = misci[i]
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == expected[i], (
            f"Index {i}: din={din[i]} → expected dout={expected[i]}, got {actual}"
        )
        if of:
            actual = int(dut.overflow.value)
            assert actual == overflow[i], f"Index {i}: din={din[i]} → expected overflow={overflow[i]}, got {actual}"
        if misc:
            actual = int(dut.misco.value)
            assert actual == misco[i], f"Index {i}: expected misco={misco[i]}, got {actual}"

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
