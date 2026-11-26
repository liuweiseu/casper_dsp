import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import json
from testbench.data_paths import module_data_dir

testdatadir = module_data_dir(__file__)

PARAMS = ["N_BITS_A", "BIN_PT_A", "N_BITS_B", "BIN_PT_B", "N_BITS_AB", "BIN_PT_AB",
          "QUANTIZATION", "OVERFLOW", "MULT_LATENCY", "ADD_LATENCY", "CONV_LATENCY",
          "IN_LATENCY", "CONJUGATED", "MULTIPLIER_IMPLEMENTATION", "PIPELINE_CMULT_EN",
          "PIPELINE_LATENCY"]
# casper async: ASYNC / PIPELINED_ENABLE are in params.json only for async sets
ASYNC_PARAMS = ["ASYNC", "PIPELINED_ENABLE"]


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


def load(path):
    """CSV of raw words -> Python ints (packed words exceed 64 bits)."""
    return [int(x) for x in path.read_text().split()]


@cocotb.test()
async def module_test(dut):
    """Test cmult module.

    Each simdataN/params.json holds one parameter set (see test_data.md).
    a, b and ab are packed {re, im} words. sim_ab.csv[i] = ab read after clock
    edge i (pre-edge read convention); the first latency values are the zero
    power-on state of the pipeline.
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    params = {name: read_param(dut, name) for name in PARAMS}
    if read_param(dut, "ASYNC"):
        params.update({name: read_param(dut, name) for name in ASYNC_PARAMS})
    cocotb.log.info(f"Testing with {params}")

    datadir = find_datadir(params)
    if datadir is None:
        cocotb.log.warning(f"No test data for {params}. Skipping.")
        return

    a = load(datadir / "sim_a.csv")
    b = load(datadir / "sim_b.csv")
    expected = load(datadir / "sim_ab.csv")
    en = load(datadir / "sim_en.csv") if (datadir / "sim_en.csv").exists() else None
    dvalid = load(datadir / "sim_dvalid.csv") if (datadir / "sim_dvalid.csv").exists() else None
    nab = params["N_BITS_AB"]
    mask = (1 << nab) - 1
    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i in range(len(expected)):
        dut.a.value = a[i]
        dut.b.value = b[i]
        if en is not None:
            dut.en.value = en[i]
        await RisingEdge(dut.clk)
        actual = int(dut.ab.value)
        assert actual == expected[i], (
            f"Index {i}: a={a[i]:#x}, b={b[i]:#x} → expected (re, im)="
            f"({expected[i] >> nab:#x}, {expected[i] & mask:#x}), "
            f"got ({actual >> nab:#x}, {actual & mask:#x})"
        )
        if dvalid is not None:
            actual = int(dut.dvalid.value)
            assert actual == dvalid[i], f"Index {i}: expected dvalid={dvalid[i]}, got {actual}"

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
