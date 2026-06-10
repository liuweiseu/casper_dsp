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
    """Test convert module.

    Drives din (and en for the async set) from CSV files and checks dout
    against the pre-computed expected output.

    Parameter sets:
        simdata0 : 18/17 -> 8/7 (SHIFT=10), Truncate + Wrap, LATENCY=1
        simdata1 : 18/17 -> 8/7 (SHIFT=10), Round +/-Inf + Saturate, LATENCY=1
        simdata2 : 12/8 -> 8/4 (SHIFT=4), Round even + Saturate, LATENCY=2, ASYNC=1
        simdata3 : 16/8 -> 16/12 (SHIFT=-4, left shift), Saturate, LATENCY=1
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    n_bits_in = int(dut.N_BITS_IN.value)
    quantization = int(dut.QUANTIZATION.value)
    is_async = int(dut.ASYNC.value)
    cocotb.log.info(
        f"Testing with N_BITS_IN={n_bits_in}, QUANTIZATION={quantization}, ASYNC={is_async}")

    if n_bits_in == 18 and quantization == 0:
        datadir = testdatadir / "simdata0"
    elif n_bits_in == 18 and quantization == 1:
        datadir = testdatadir / "simdata1"
    elif n_bits_in == 12 and quantization == 2:
        datadir = testdatadir / "simdata2"
    elif n_bits_in == 16:
        datadir = testdatadir / "simdata3"
    else:
        raise ValueError("No test data for this parameter combination")

    sim_in = np.loadtxt(datadir / "sim_in.csv", dtype=int).tolist()
    sim_out = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    en_f = datadir / "sim_in_en.csv"
    sim_in_en = np.loadtxt(en_f, dtype=int).tolist() if en_f.exists() else [1] * len(sim_in)

    dut.rst.value = 0

    for i in range(len(sim_in)):
        dut.din.value = sim_in[i]
        dut.en.value = sim_in_en[i]
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == sim_out[i], \
            f"Output mismatch! Expected {hex(sim_out[i])}, got {hex(actual)}, index: {i}"
