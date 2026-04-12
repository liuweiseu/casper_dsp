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
    """Test register module.

    Drives d (and conditionally en/rst) before each rising edge and compares q
    against the expected value in simdata<N>/sim_out.csv after the edge.

    Parameter sets:
        simdata0 : USE_RST=1, USE_ENABLE=1, INIT_VAL=0,  BITWIDTH=4 — reset + enable, reset to 0
        simdata1 : USE_RST=1, USE_ENABLE=0, INIT_VAL=0,  BITWIDTH=4 — reset only, reset to 0
        simdata2 : USE_RST=0, USE_ENABLE=1, INIT_VAL=0,  BITWIDTH=4 — enable only, no reset
        simdata3 : USE_RST=0, USE_ENABLE=0, INIT_VAL=0,  BITWIDTH=4 — direct register
        simdata4 : USE_RST=1, USE_ENABLE=1, INIT_VAL=7,  BITWIDTH=4 — reset + enable, reset to 7
        simdata5 : USE_RST=1, USE_ENABLE=0, INIT_VAL=10, BITWIDTH=4 — reset only, reset to 10
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    bitwidth   = int(dut.BITWIDTH.value)
    use_rst    = int(dut.USE_RST.value)
    use_enable = int(dut.USE_ENABLE.value)
    init_val   = int(dut.INIT_VAL.value)
    cocotb.log.info(
        f"Testing with BITWIDTH={bitwidth}, USE_RST={use_rst}, "
        f"USE_ENABLE={use_enable}, INIT_VAL={init_val}"
    )

    if   use_rst == 1 and use_enable == 1 and init_val == 0:
        datadir = testdatadir / "simdata0"
    elif use_rst == 1 and use_enable == 0 and init_val == 0:
        datadir = testdatadir / "simdata1"
    elif use_rst == 0 and use_enable == 1:
        datadir = testdatadir / "simdata2"
    elif use_rst == 0 and use_enable == 0:
        datadir = testdatadir / "simdata3"
    elif use_rst == 1 and use_enable == 1 and init_val == 7:
        datadir = testdatadir / "simdata4"
    elif use_rst == 1 and use_enable == 0 and init_val == 10:
        datadir = testdatadir / "simdata5"
    else:
        cocotb.log.warning(
            f"No test data for USE_RST={use_rst}, USE_ENABLE={use_enable}, "
            f"INIT_VAL={init_val}. Skipping."
        )
        return

    sim_d    = np.loadtxt(datadir / "sim_d.csv",   dtype=int).tolist()
    expected = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()

    sim_rst = np.loadtxt(datadir / "sim_rst.csv", dtype=int).tolist() if use_rst    else None
    sim_en  = np.loadtxt(datadir / "sim_en.csv",  dtype=int).tolist() if use_enable else None

    for i, (d_val, exp) in enumerate(zip(sim_d, expected)):
        dut.d.value   = d_val
        dut.rst.value = int(sim_rst[i]) if sim_rst is not None else 0
        dut.en.value  = int(sim_en[i])  if sim_en  is not None else 0
        await RisingEdge(dut.clk)
        actual = int(dut.q.value)
        assert actual == exp, (
            f"Index {i}: d={d_val}, en={dut.en.value}, rst={dut.rst.value} "
            f"→ expected q={exp}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_d)} cycles verified")
