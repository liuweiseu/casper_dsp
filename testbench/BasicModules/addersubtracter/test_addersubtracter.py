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
    """Test addersubtracter module.

    Drives a/b (and cin/sub/en where applicable) from CSV files and checks
    c (and cout for the carry-out set) against the pre-computed output.

    Parameter sets:
        simdata0 : MODE=1 (subtract), signed 18/17, LATENCY=1
        simdata1 : MODE=0 (add), signed 8/7, LATENCY=2, carry-in + carry-out
        simdata2 : MODE=2 (runtime sub), signed 8/7, LATENCY=2, ASYNC=1
    """
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    mode = int(dut.MODE.value)
    is_async = int(dut.ASYNC.value)
    use_cout = int(dut.USE_CARRY_OUT.value)
    cocotb.log.info(f"Testing with MODE={mode}, ASYNC={is_async}, USE_CARRY_OUT={use_cout}")

    if mode == 1:
        datadir = testdatadir / "simdata0"
    elif mode == 0:
        datadir = testdatadir / "simdata1"
    elif mode == 2:
        datadir = testdatadir / "simdata2"
    else:
        raise ValueError("No test data for this parameter combination")

    sim_in_a = np.loadtxt(datadir / "sim_in_a.csv", dtype=int).tolist()
    sim_in_b = np.loadtxt(datadir / "sim_in_b.csv", dtype=int).tolist()
    sim_out = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    n = len(sim_in_a)

    cin_f = datadir / "sim_in_cin.csv"
    sub_f = datadir / "sim_in_sub.csv"
    en_f = datadir / "sim_in_en.csv"
    cout_f = datadir / "sim_out_cout.csv"
    sim_in_cin = np.loadtxt(cin_f, dtype=int).tolist() if cin_f.exists() else [0] * n
    sim_in_sub = np.loadtxt(sub_f, dtype=int).tolist() if sub_f.exists() else [0] * n
    sim_in_en = np.loadtxt(en_f, dtype=int).tolist() if en_f.exists() else [1] * n
    sim_out_cout = np.loadtxt(cout_f, dtype=int).tolist() if cout_f.exists() else None

    dut.rst.value = 0

    for i in range(n):
        dut.a.value = sim_in_a[i]
        dut.b.value = sim_in_b[i]
        dut.cin.value = sim_in_cin[i]
        dut.sub.value = sim_in_sub[i]
        dut.en.value = sim_in_en[i]
        await RisingEdge(dut.clk)
        actual = int(dut.c.value)
        assert actual == sim_out[i], \
            f"Output mismatch! Expected {hex(sim_out[i])}, got {hex(actual)}, index: {i}"
        if sim_out_cout is not None:
            actual_cout = int(dut.cout.value)
            assert actual_cout == sim_out_cout[i], \
                f"Carry mismatch! Expected {sim_out_cout[i]}, got {actual_cout}, index: {i}"
