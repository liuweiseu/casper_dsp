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
    """Test cmult module.

    Drives packed complex a/b (and en for the async set) from CSV files and
    checks ab (and dvalid for the async set) against the pre-computed output
    of a cycle-accurate structural model.

    Parameter sets:
        simdata0 : 8/7 x 8/7 -> 17/14 (SHIFT=0), Truncate + Wrap, latency 4
        simdata1 : 8/7 x 8/7 -> 8/7 (SHIFT=7), Round +/-Inf + Saturate, latency 4
        simdata2 : as simdata0 + ASYNC=1, PIPELINED_ENABLE=1, IN_LATENCY=1, latency 5
        simdata3 : as simdata0 + CONJUGATED=1 (computes a * conj(b))
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    n_bits_ab = int(dut.N_BITS_AB.value)
    conjugated = int(dut.CONJUGATED.value)
    is_async = int(dut.ASYNC.value)
    cocotb.log.info(
        f"Testing with N_BITS_AB={n_bits_ab}, CONJUGATED={conjugated}, ASYNC={is_async}")

    if is_async == 1:
        datadir = testdatadir / "simdata2"
    elif conjugated == 1:
        datadir = testdatadir / "simdata3"
    elif n_bits_ab == 8:
        datadir = testdatadir / "simdata1"
    elif n_bits_ab == 17:
        datadir = testdatadir / "simdata0"
    else:
        raise ValueError("No test data for this parameter combination")

    sim_in_a = np.loadtxt(datadir / "sim_in_a.csv", dtype=int).tolist()
    sim_in_b = np.loadtxt(datadir / "sim_in_b.csv", dtype=int).tolist()
    sim_out = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    n = len(sim_in_a)

    en_f = datadir / "sim_in_en.csv"
    dv_f = datadir / "sim_out_dvalid.csv"
    sim_in_en = np.loadtxt(en_f, dtype=int).tolist() if en_f.exists() else [1] * n
    sim_out_dv = np.loadtxt(dv_f, dtype=int).tolist() if dv_f.exists() else None

    dut.rst.value = 0

    for i in range(n):
        dut.a.value = sim_in_a[i]
        dut.b.value = sim_in_b[i]
        dut.en.value = sim_in_en[i]
        await RisingEdge(dut.clk)
        actual = int(dut.ab.value)
        assert actual == sim_out[i], \
            f"Output mismatch! Expected {hex(sim_out[i])}, got {hex(actual)}, index: {i}"
        if sim_out_dv is not None:
            actual_dv = int(dut.dvalid.value)
            assert actual_dv == sim_out_dv[i], \
                f"dvalid mismatch! Expected {sim_out_dv[i]}, got {actual_dv}, index: {i}"
