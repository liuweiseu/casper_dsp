import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import numpy as np
from testbench.data_paths import find_data_dir, module_data_dir

testdatadir = module_data_dir(__file__)

EQ = 0
NE = 1
LT = 2
GT = 3
LE = 4
GE = 5

# Parameters matched against simdataN/params.json
# (a key missing from an older params.json takes its PARAM_DEFAULTS value)
PARAMS = ['NBITS', 'COMP', 'LATENCY', 'SIGNED', 'USE_ENABLE']
PARAM_DEFAULTS = {'USE_ENABLE': 0}


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
        simdata8+ : SIGNED / USE_ENABLE sets, matched by params.json (see
                    test_data.md); en driven from sim_en.csv when present
    """
    nbits   = int(dut.NBITS.value)
    comp    = int(dut.COMP.value)
    latency = int(dut.LATENCY.value)
    cocotb.log.info(
        f"Testing with NBITS={nbits}, COMP={comp}, LATENCY={latency}"
    )

    datadir = find_data_dir(dut, testdatadir, PARAMS, PARAM_DEFAULTS)

    sim_a   = np.loadtxt(datadir / "sim_a.csv",   dtype=int).tolist()
    sim_b   = np.loadtxt(datadir / "sim_b.csv",   dtype=int).tolist()
    sim_out = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    en_file = datadir / "sim_en.csv"
    sim_en  = np.loadtxt(en_file, dtype=int).tolist() if en_file.exists() else None
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
            if sim_en is not None:
                dut.en.value = sim_en[i]
            await RisingEdge(dut.clk)
            actual = int(dut.out.value)
            assert actual == sim_out[i], (
                f"Index {i}: a={sim_a[i]}, b={sim_b[i]} "
                f"→ expected out={sim_out[i]}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {len(sim_out)} cycles verified")
