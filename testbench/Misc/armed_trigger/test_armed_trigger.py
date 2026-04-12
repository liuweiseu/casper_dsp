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
    """Test armed_trigger module.

    Drives arm and trig_in before each rising edge and compares trig_out
    against the expected value in sim_trig_out.csv after the edge.

    Test sequence (simdata0) covers:
        - Default armed state at power-on (INIT_VAL=1 in internal register)
        - One-shot behaviour: fires once then disarms automatically
        - trig_in held high while disarmed does not re-fire
        - Re-arm via arm pulse restores armed state
        - arm pulse arriving while trig_in is high: rst takes priority, arms cleanly
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    datadir = testdatadir / "simdata0"

    sim_arm     = np.loadtxt(datadir / "sim_arm.csv",      dtype=int).tolist()
    sim_trig_in = np.loadtxt(datadir / "sim_trig_in.csv",  dtype=int).tolist()
    expected    = np.loadtxt(datadir / "sim_trig_out.csv", dtype=int).tolist()

    cocotb.log.info(f"Loaded {len(sim_arm)} test vectors from {datadir.name}/")

    for i, (arm_val, trig_in_val, exp) in enumerate(
        zip(sim_arm, sim_trig_in, expected)
    ):
        dut.arm.value     = arm_val
        dut.trig_in.value = trig_in_val
        await RisingEdge(dut.clk)
        actual = int(dut.trig_out.value)
        assert actual == exp, (
            f"Index {i}: arm={arm_val}, trig_in={trig_in_val} "
            f"→ expected trig_out={exp}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_arm)} cycles verified")
