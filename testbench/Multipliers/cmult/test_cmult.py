import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import json

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

PARAMS = ["N_BITS_A", "BIN_PT_A", "N_BITS_B", "BIN_PT_B", "N_BITS_AB", "BIN_PT_AB",
          "QUANTIZATION", "OVERFLOW", "MULT_LATENCY", "ADD_LATENCY", "CONV_LATENCY",
          "IN_LATENCY", "CONJUGATED", "MULTIPLIER_IMPLEMENTATION", "PIPELINE_CMULT_EN",
          "PIPELINE_LATENCY"]


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
    cocotb.log.info(f"Testing with {params}")

    datadir = find_datadir(params)
    if datadir is None:
        cocotb.log.warning(f"No test data for {params}. Skipping.")
        return

    a = load(datadir / "sim_a.csv")
    b = load(datadir / "sim_b.csv")
    expected = load(datadir / "sim_ab.csv")
    nab = params["N_BITS_AB"]
    mask = (1 << nab) - 1
    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i in range(len(expected)):
        dut.a.value = a[i]
        dut.b.value = b[i]
        await RisingEdge(dut.clk)
        actual = int(dut.ab.value)
        assert actual == expected[i], (
            f"Index {i}: a={a[i]:#x}, b={b[i]:#x} → expected (re, im)="
            f"({expected[i] >> nab:#x}, {expected[i] & mask:#x}), "
            f"got ({actual >> nab:#x}, {actual & mask:#x})"
        )

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
