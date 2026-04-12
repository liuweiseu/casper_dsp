import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


@cocotb.test()
async def module_test(dut):
    """Test multiplexer module.

    For LATENCY=0 (combinational): drives inputs, waits 1 ns, reads dout.
    For LATENCY>=1 (pipelined): drives inputs before each rising edge,
    reads dout after the edge (pre-edge read convention).

    sim_out[i] = dout value before clock edge i (LATENCY>=1), or the
    immediate combinational result (LATENCY=0).

    Parameter sets:
        simdata0 : NBITS=8, NINPUTS=2, LATENCY=1
        simdata1 : NBITS=8, NINPUTS=4, LATENCY=1
        simdata2 : NBITS=8, NINPUTS=2, LATENCY=0 (combinational)
        simdata3 : NBITS=8, NINPUTS=2, LATENCY=2
    """
    nbits   = int(dut.NBITS.value)
    ninputs = int(dut.NINPUTS.value)
    latency = int(dut.LATENCY.value)
    cocotb.log.info(
        f"Testing with NBITS={nbits}, NINPUTS={ninputs}, LATENCY={latency}"
    )

    if   nbits == 8 and ninputs == 2 and latency == 1:
        datadir = testdatadir / "simdata0"
    elif nbits == 8 and ninputs == 4 and latency == 1:
        datadir = testdatadir / "simdata1"
    elif nbits == 8 and ninputs == 2 and latency == 0:
        datadir = testdatadir / "simdata2"
    elif nbits == 8 and ninputs == 2 and latency == 2:
        datadir = testdatadir / "simdata3"
    else:
        cocotb.log.warning(
            f"No test data for NBITS={nbits}, NINPUTS={ninputs}, "
            f"LATENCY={latency}. Skipping."
        )
        return

    sim_inputs = [
        np.loadtxt(datadir / f"sim_in{k}.csv", dtype=int).tolist()
        for k in range(ninputs)
    ]
    sim_sel  = np.loadtxt(datadir / "sim_sel.csv",  dtype=int).tolist()
    expected = np.loadtxt(datadir / "sim_out.csv",  dtype=int).tolist()

    cocotb.log.info(f"Loaded {len(expected)} test vectors from {datadir.name}/")

    if latency == 0:
        for i in range(len(expected)):
            # cocotb/Verilator unpacked-array convention: list[k] → din[k] (direct mapping)
            dut.din.value = [sim_inputs[k][i] for k in range(ninputs)]
            dut.sel.value = sim_sel[i]
            await Timer(1, units="ns")
            actual = int(dut.dout.value)
            assert actual == expected[i], (
                f"Index {i}: sel={sim_sel[i]}, "
                f"inputs={[sim_inputs[k][i] for k in range(ninputs)]} "
                f"→ expected dout={expected[i]}, got {actual}"
            )
    else:
        clock = Clock(dut.clk, 10, units="ns")
        cocotb.start_soon(clock.start())
        for i in range(len(expected)):
            # cocotb/Verilator unpacked-array convention: list[k] → din[k] (direct mapping)
            dut.din.value = [sim_inputs[k][i] for k in range(ninputs)]
            dut.sel.value = sim_sel[i]
            await RisingEdge(dut.clk)
            actual = int(dut.dout.value)
            assert actual == expected[i], (
                f"Index {i}: sel={sim_sel[i]}, "
                f"inputs={[sim_inputs[k][i] for k in range(ninputs)]} "
                f"→ expected dout={expected[i]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
