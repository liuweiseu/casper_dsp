import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import numpy as np
from testbench.data_paths import find_data_dir, module_data_dir

testdatadir = module_data_dir(__file__)


# Parameters matched against simdataN/params.json
PARAMS = ['NBITS', 'LATENCY', 'USE_ENABLE']


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

    datadir = find_data_dir(dut, testdatadir, PARAMS)

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
