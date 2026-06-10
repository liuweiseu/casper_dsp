import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import numpy as np

# testdatadir points to the corresponding test_data subdirectory
_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


@cocotb.test()
async def module_test(dut):
    """Test multiplier module.

    Drives a/b (and en for the async set) from CSV files and checks p
    against the pre-computed expected output.

    Parameter sets:
        simdata0 : PRECISION=0 (Full), signed 18x18, LATENCY=2
        simdata1 : PRECISION=1, 8x8 -> 8 (SHIFT=7), Round +/-Inf, Saturate, LATENCY=2
        simdata2 : PRECISION=0 (Full), signed 8x8, LATENCY=2, ASYNC=1 (random en)
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    n_bits_a = int(dut.N_BITS_A.value)
    precision = int(dut.PRECISION.value)
    is_async = int(dut.ASYNC.value)
    cocotb.log.info(
        f"Testing with N_BITS_A={n_bits_a}, PRECISION={precision}, ASYNC={is_async}")

    if precision == 0 and is_async == 0 and n_bits_a == 18:
        datadir = testdatadir / "simdata0"
    elif precision == 1 and is_async == 0 and n_bits_a == 8:
        datadir = testdatadir / "simdata1"
    elif precision == 0 and is_async == 1 and n_bits_a == 8:
        datadir = testdatadir / "simdata2"
    else:
        raise ValueError("No test data for this parameter combination")

    sim_in_a = np.loadtxt(datadir / "sim_in_a.csv", dtype=int).tolist()
    sim_in_b = np.loadtxt(datadir / "sim_in_b.csv", dtype=int).tolist()
    sim_out = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    if is_async:
        sim_in_en = np.loadtxt(datadir / "sim_in_en.csv", dtype=int).tolist()
    else:
        sim_in_en = [1] * len(sim_in_a)

    dut.rst.value = 0

    for i in range(len(sim_in_a)):
        dut.a.value = sim_in_a[i]
        dut.b.value = sim_in_b[i]
        dut.en.value = sim_in_en[i]
        await RisingEdge(dut.clk)
        actual = int(dut.p.value)
        assert actual == sim_out[i], \
            f"Output mismatch! Expected {hex(sim_out[i])}, got {hex(actual)}, index: {i}"
