import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


@cocotb.test()
async def module_test(dut):
    """Test pulse_ext module.

    Drives 'in', reads 'out' before each rising edge (pre-edge convention).

    Counter is free-running with INIT_VAL=0, so out=1 for the first PULSE_LEN
    cycles at power-on (counter counts 0→PULSE_LEN before settling).
    After that, a rising edge on 'in' clears the counter to 0 (via rst) and
    out is asserted for PULSE_LEN cycles starting 2 cycles later
    (1 cycle edge_detect latency + 1 cycle counter clear).
    A second trigger during an active pulse re-arms from zero (pulse extended).

    Parameter sets:
        simdata0 : PULSE_LEN=3 — single rising edge
        simdata1 : PULSE_LEN=5 — two separated rising edges
        simdata2 : PULSE_LEN=4 — second trigger during active pulse (re-arm)
    """
    pulse_len = int(dut.PULSE_LEN.value)
    cocotb.log.info(f"Testing with PULSE_LEN={pulse_len}")

    if   pulse_len == 3:
        datadir = testdatadir / "simdata0"
    elif pulse_len == 5:
        datadir = testdatadir / "simdata1"
    elif pulse_len == 4:
        datadir = testdatadir / "simdata2"
    else:
        cocotb.log.warning(f"No test data for PULSE_LEN={pulse_len}. Skipping.")
        return

    sim_in  = np.loadtxt(datadir / "sim_in.csv",  dtype=int).tolist()
    sim_out = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(sim_out)} test vectors from {datadir.name}/")

    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    in_port = getattr(dut, "in")

    for i in range(len(sim_out)):
        in_port.value = sim_in[i]
        await RisingEdge(dut.clk)
        actual = int(dut.out.value)
        assert actual == sim_out[i], (
            f"Index {i}: in={sim_in[i]} → expected out={sim_out[i]}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_out)} cycles verified")
