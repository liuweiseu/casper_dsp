import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import json
import numpy as np

# testdatadir points to the corresponding test_data subdirectory
_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

# Parameters matched against simdataN/params.json
PARAMS = ['LATENCY', 'BITWIDTH', 'USE_RST', 'USE_ENABLE']


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
    """Test delay module.

    Drives din (and rst / en when the data set has sim_rst.csv / sim_en.csv)
    before each rising edge and compares dout after it against sim_dout.csv
    (pre-edge read convention). LATENCY=0 is combinational: drive, wait
    1 ns, read.

    Parameter sets (matched by simdataN/params.json):
        simdata0 : LATENCY=1, BITWIDTH=3 — original set
        simdata1 : LATENCY=0, BITWIDTH=4 — wire
        simdata2 : LATENCY=3, BITWIDTH=4, USE_RST=1, USE_ENABLE=1
        simdata3 : LATENCY=2, BITWIDTH=5, USE_ENABLE=1
        simdata4 : LATENCY=1, BITWIDTH=3, USE_RST=1
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    latency = int(dut.LATENCY.value)
    cocotb.log.info("Testing with " + ", ".join(
        f"{k}={int(getattr(dut, k).value)}" for k in PARAMS))

    datadir = find_param_datadir(dut)
    assert datadir is not None, "No simdataN/params.json matches the DUT parameters"

    expected = np.loadtxt(datadir / "sim_dout.csv", dtype=int).tolist()
    inputs = {}
    for port in ["din", "rst", "en"]:
        f = datadir / f"sim_{port}.csv"
        if f.exists():
            inputs[port] = np.loadtxt(f, dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(expected)} cycles from {datadir.name} "
                    f"(driving {', '.join(inputs)})")

    for i in range(len(expected)):
        for port, vals in inputs.items():
            getattr(dut, port).value = vals[i]
        if latency == 0:
            await Timer(1, units="ns")
        else:
            await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        drv = ", ".join(f"{port}={vals[i]}" for port, vals in inputs.items())
        assert actual == expected[i], (
            f"Index {i}: {drv} → expected dout={expected[i]}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
