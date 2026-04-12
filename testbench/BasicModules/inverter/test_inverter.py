import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


@cocotb.test()
async def module_test(dut):
    """Test inverter module.

    For LATENCY=0 (combinational): drive din, wait 1 ns, read dout.
      sim_out[i] = ~din[i] directly (no clock-edge offset).
    For LATENCY>=1 (pipelined): drive din, await RisingEdge, read dout.
      sim_out[i] = pre-edge value = ~din[i-LATENCY], with leading zeros.

    Parameter sets:
        simdata0 : NBITS=4, LATENCY=0 — combinational pass-through
        simdata1 : NBITS=4, LATENCY=1 — single pipeline stage
        simdata2 : NBITS=4, LATENCY=2 — two pipeline stages
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    nbits   = int(dut.NBITS.value)
    latency = int(dut.LATENCY.value)
    cocotb.log.info(f"Testing with NBITS={nbits}, LATENCY={latency}")

    if   nbits == 4 and latency == 0:
        datadir = testdatadir / "simdata0"
    elif nbits == 4 and latency == 1:
        datadir = testdatadir / "simdata1"
    elif nbits == 4 and latency == 2:
        datadir = testdatadir / "simdata2"
    else:
        cocotb.log.warning(
            f"No test data for NBITS={nbits}, LATENCY={latency}. Skipping."
        )
        return

    sim_d    = np.loadtxt(datadir / "sim_d.csv",   dtype=int).tolist()
    expected = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i, (d_val, exp) in enumerate(zip(sim_d, expected)):
        dut.din.value = d_val
        if latency == 0:
            await Timer(1, units="ns")
        else:
            await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == exp, (
            f"Index {i}: din={d_val} → expected dout={exp}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_d)} cycles verified")
