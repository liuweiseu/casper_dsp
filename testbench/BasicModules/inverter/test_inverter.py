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
PARAMS = ['NBITS', 'LATENCY', 'USE_ENABLE']


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
    """Test inverter module.

    For LATENCY=0 (combinational): drive din, wait 1 ns, read dout.
      sim_dout[i] = ~din[i] directly (no clock-edge offset).
    For LATENCY>=1 (pipelined): drive din, await RisingEdge, read dout.
      sim_dout[i] = pre-edge value = ~din[i-LATENCY], with leading zeros.

    Parameter sets:
        simdata0 : NBITS=4, LATENCY=0 — combinational pass-through
        simdata1 : NBITS=4, LATENCY=1 — single pipeline stage
        simdata2 : NBITS=4, LATENCY=2 — two pipeline stages
        simdata3 : NBITS=4, LATENCY=2, USE_ENABLE=1 — en driven from sim_en.csv
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    nbits   = int(dut.NBITS.value)
    latency = int(dut.LATENCY.value)
    cocotb.log.info(f"Testing with NBITS={nbits}, LATENCY={latency}")

    datadir = find_param_datadir(dut)
    if datadir is not None:
        pass
    elif int(dut.USE_ENABLE.value):
        assert False, "No params.json matches this USE_ENABLE configuration"
    elif nbits == 4 and latency == 0:
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

    sim_d    = np.loadtxt(datadir / "sim_din.csv",   dtype=int).tolist()
    expected = np.loadtxt(datadir / "sim_dout.csv", dtype=int).tolist()
    en_file  = datadir / "sim_en.csv"
    sim_en   = np.loadtxt(en_file, dtype=int).tolist() if en_file.exists() else None
    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i, (d_val, exp) in enumerate(zip(sim_d, expected)):
        dut.din.value = d_val
        if sim_en is not None:
            dut.en.value = sim_en[i]
        if latency == 0:
            await Timer(1, units="ns")
        else:
            await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == exp, (
            f"Index {i}: din={d_val} → expected dout={exp}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_d)} cycles verified")
