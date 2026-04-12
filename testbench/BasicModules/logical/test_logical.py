import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

AND  = 0
NAND = 1
OR   = 2
NOR  = 3
XOR  = 4
XNOR = 5


@cocotb.test()
async def module_test(dut):
    """Test logical module.

    sim_out[i] = dout value before clock edge i (pre-edge read convention).
    Initial shift_reg = 0, so sim_out[0..LATENCY-1] = 0.

    Parameter sets:
        simdata0 : FUNC=0(AND),  NBITS=4, NINPUTS=2, LATENCY=1
        simdata1 : FUNC=1(NAND), NBITS=4, NINPUTS=2, LATENCY=1
        simdata2 : FUNC=2(OR),   NBITS=4, NINPUTS=2, LATENCY=1
        simdata3 : FUNC=3(NOR),  NBITS=4, NINPUTS=2, LATENCY=1
        simdata4 : FUNC=4(XOR),  NBITS=4, NINPUTS=2, LATENCY=1
        simdata5 : FUNC=5(XNOR), NBITS=4, NINPUTS=2, LATENCY=1
        simdata6 : FUNC=0(AND),  NBITS=4, NINPUTS=3, LATENCY=1
        simdata7 : FUNC=4(XOR),  NBITS=4, NINPUTS=2, LATENCY=2
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    nbits   = int(dut.NBITS.value)
    ninputs = int(dut.NINPUTS.value)
    latency = int(dut.LATENCY.value)
    func    = int(dut.FUNC.value)

    cocotb.log.info(
        f"Testing with NBITS={nbits}, NINPUTS={ninputs}, "
        f"LATENCY={latency}, FUNC={func}"
    )

    if   func == AND  and nbits == 4 and ninputs == 2 and latency == 1:
        datadir = testdatadir / "simdata0"
    elif func == NAND and nbits == 4 and ninputs == 2 and latency == 1:
        datadir = testdatadir / "simdata1"
    elif func == OR   and nbits == 4 and ninputs == 2 and latency == 1:
        datadir = testdatadir / "simdata2"
    elif func == NOR  and nbits == 4 and ninputs == 2 and latency == 1:
        datadir = testdatadir / "simdata3"
    elif func == XOR  and nbits == 4 and ninputs == 2 and latency == 1:
        datadir = testdatadir / "simdata4"
    elif func == XNOR and nbits == 4 and ninputs == 2 and latency == 1:
        datadir = testdatadir / "simdata5"
    elif func == AND  and nbits == 4 and ninputs == 3 and latency == 1:
        datadir = testdatadir / "simdata6"
    elif func == XOR  and nbits == 4 and ninputs == 2 and latency == 2:
        datadir = testdatadir / "simdata7"
    else:
        cocotb.log.warning(
            f"No test data for FUNC={func}, NBITS={nbits}, "
            f"NINPUTS={ninputs}, LATENCY={latency}. Skipping."
        )
        return

    sim_inputs = [
        np.loadtxt(datadir / f"sim_in{k}.csv", dtype=int).tolist()
        for k in range(1, ninputs + 1)
    ]
    expected = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()

    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i in range(len(expected)):
        # cocotb unpacked-array convention: [din[NINPUTS-1], ..., din[0]]
        # sim_inputs[0] -> din[0] (sim_in1), sim_inputs[1] -> din[1] (sim_in2), ...
        dut.din.value = [sim_inputs[k][i] for k in range(ninputs - 1, -1, -1)]
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == expected[i], (
            f"Index {i}: inputs={[sim_inputs[k][i] for k in range(ninputs)]} "
            f"→ expected dout={expected[i]}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
