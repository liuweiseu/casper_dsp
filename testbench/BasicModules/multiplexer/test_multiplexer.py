import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import json
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


# Parameters matched against simdataN/params.json (USE_ENABLE sets, generated
# by test_data/scripts/gen_basic_test_data.py); the original sets have no
# params.json and are selected by the parameter checks below.
PARAMS = ['NBITS', 'NINPUTS', 'LATENCY', 'USE_ENABLE']


def find_param_datadir(dut):
    """Return the simdataN with a params.json matching the DUT, or None."""
    dut_params = {name: int(getattr(dut, name).value) for name in PARAMS}
    for d in sorted(testdatadir.glob("simdata*")):
        pj = d / "params.json"
        if pj.exists():
            p = json.loads(pj.read_text())
            if {k: p[k] for k in PARAMS} == dut_params:
                return d
    return None


@cocotb.test()
async def module_test(dut):
    """Test multiplexer module.

    For LATENCY=0 (combinational): drives inputs, waits 1 ns, reads dout.
    For LATENCY>=1 (pipelined): drives inputs before each rising edge,
    reads dout after the edge (pre-edge read convention).

    sim_dout[i] = dout value before clock edge i (LATENCY>=1), or the
    immediate combinational result (LATENCY=0).

    Parameter sets:
        simdata0 : NBITS=8, NINPUTS=2, LATENCY=1
        simdata1 : NBITS=8, NINPUTS=4, LATENCY=1
        simdata2 : NBITS=8, NINPUTS=2, LATENCY=0 (combinational)
        simdata3 : NBITS=8, NINPUTS=2, LATENCY=2
        simdata4 : NBITS=8, NINPUTS=4, LATENCY=2, USE_ENABLE=1 (en driven
                   from sim_en.csv)
    """
    nbits   = int(dut.NBITS.value)
    ninputs = int(dut.NINPUTS.value)
    latency = int(dut.LATENCY.value)
    cocotb.log.info(
        f"Testing with NBITS={nbits}, NINPUTS={ninputs}, LATENCY={latency}"
    )

    datadir = find_param_datadir(dut)
    if datadir is not None:
        pass
    elif int(dut.USE_ENABLE.value):
        assert False, "No params.json matches this USE_ENABLE configuration"
    elif nbits == 8 and ninputs == 2 and latency == 1:
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

    # sim_din.csv: row i = [din[0], ..., din[NINPUTS-1]]
    sim_din  = np.loadtxt(datadir / "sim_din.csv", dtype=int, ndmin=2).tolist()
    sim_sel  = np.loadtxt(datadir / "sim_sel.csv",  dtype=int).tolist()
    expected = np.loadtxt(datadir / "sim_dout.csv",  dtype=int).tolist()
    en_file  = datadir / "sim_en.csv"
    sim_en   = np.loadtxt(en_file, dtype=int).tolist() if en_file.exists() else None

    cocotb.log.info(f"Loaded {len(expected)} test vectors from {datadir.name}/")

    if latency == 0:
        for i in range(len(expected)):
            # cocotb/Verilator unpacked-array convention: list[k] → din[k] (direct mapping)
            dut.din.value = sim_din[i]
            dut.sel.value = sim_sel[i]
            await Timer(1, units="ns")
            actual = int(dut.dout.value)
            assert actual == expected[i], (
                f"Index {i}: sel={sim_sel[i]}, "
                f"din={sim_din[i]} "
                f"→ expected dout={expected[i]}, got {actual}"
            )
    else:
        clock = Clock(dut.clk, 10, units="ns")
        cocotb.start_soon(clock.start())
        for i in range(len(expected)):
            # cocotb/Verilator unpacked-array convention: list[k] → din[k] (direct mapping)
            dut.din.value = sim_din[i]
            dut.sel.value = sim_sel[i]
            if sim_en is not None:
                dut.en.value = sim_en[i]
            await RisingEdge(dut.clk)
            actual = int(dut.dout.value)
            assert actual == expected[i], (
                f"Index {i}: sel={sim_sel[i]}, "
                f"din={sim_din[i]} "
                f"→ expected dout={expected[i]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
