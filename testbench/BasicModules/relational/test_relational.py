import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

EQ = 0
NE = 1
LT = 2
GT = 3
LE = 4
GE = 5


@cocotb.test()
async def module_test(dut):
    """Test relational module.

    For LATENCY=0 (combinational): drives inputs, waits 1 ns, reads out.
    For LATENCY>=1 (pipelined): drives inputs before each rising edge,
    reads out after the edge (pre-edge read convention).

    sim_out[i] = result(a[i], b[i])        for LATENCY=0
    sim_out[i] = result(a[i-L], b[i-L])    for LATENCY=L (0 for first L cycles)

    Parameter sets:
        simdata0 : COMP=0(eq), NBITS=4, LATENCY=1
        simdata1 : COMP=1(ne), NBITS=4, LATENCY=1
        simdata2 : COMP=2(lt), NBITS=4, LATENCY=1
        simdata3 : COMP=3(gt), NBITS=4, LATENCY=1
        simdata4 : COMP=4(le), NBITS=4, LATENCY=1
        simdata5 : COMP=5(ge), NBITS=4, LATENCY=1
        simdata6 : COMP=2(lt), NBITS=4, LATENCY=0 (combinational)
        simdata7 : COMP=0(eq), NBITS=8, LATENCY=2 (multi-stage pipeline)
    """
    nbits   = int(dut.NBITS.value)
    comp    = int(dut.COMP.value)
    latency = int(dut.LATENCY.value)
    cocotb.log.info(
        f"Testing with NBITS={nbits}, COMP={comp}, LATENCY={latency}"
    )

    if   comp == EQ and nbits == 4 and latency == 1:
        datadir = testdatadir / "simdata0"
    elif comp == NE and nbits == 4 and latency == 1:
        datadir = testdatadir / "simdata1"
    elif comp == LT and nbits == 4 and latency == 1:
        datadir = testdatadir / "simdata2"
    elif comp == GT and nbits == 4 and latency == 1:
        datadir = testdatadir / "simdata3"
    elif comp == LE and nbits == 4 and latency == 1:
        datadir = testdatadir / "simdata4"
    elif comp == GE and nbits == 4 and latency == 1:
        datadir = testdatadir / "simdata5"
    elif comp == LT and nbits == 4 and latency == 0:
        datadir = testdatadir / "simdata6"
    elif comp == EQ and nbits == 8 and latency == 2:
        datadir = testdatadir / "simdata7"
    else:
        cocotb.log.warning(
            f"No test data for COMP={comp}, NBITS={nbits}, "
            f"LATENCY={latency}. Skipping."
        )
        return

    sim_a   = np.loadtxt(datadir / "sim_a.csv",   dtype=int).tolist()
    sim_b   = np.loadtxt(datadir / "sim_b.csv",   dtype=int).tolist()
    sim_out = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(sim_out)} test vectors from {datadir.name}/")

    if latency == 0:
        for i in range(len(sim_out)):
            dut.a.value = sim_a[i]
            dut.b.value = sim_b[i]
            await Timer(1, units="ns")
            actual = int(dut.out.value)
            assert actual == sim_out[i], (
                f"Index {i}: a={sim_a[i]}, b={sim_b[i]} "
                f"→ expected out={sim_out[i]}, got {actual}"
            )
    else:
        clock = Clock(dut.clk, 10, units="ns")
        cocotb.start_soon(clock.start())
        for i in range(len(sim_out)):
            dut.a.value = sim_a[i]
            dut.b.value = sim_b[i]
            await RisingEdge(dut.clk)
            actual = int(dut.out.value)
            assert actual == sim_out[i], (
                f"Index {i}: a={sim_a[i]}, b={sim_b[i]} "
                f"→ expected out={sim_out[i]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {len(sim_out)} cycles verified")
