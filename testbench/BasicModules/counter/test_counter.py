import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import numpy as np
from testbench.data_paths import find_data_dir, module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

# Must match localparam values in counter.sv
FREE_RUNNING = 0
COUNT_LIMIT  = 1
DIR_UP       = 0
DIR_DOWN     = 1

DIR_UP_DOWN  = 2

# Parameters matched against simdataN/params.json. A key missing from an
# older params.json takes its default from PARAM_DEFAULTS.
PARAMS = ['COUNTER_TYPE', 'NBITS', 'COUNT_TO_VAL', 'COUNT_DIR', 'INIT_VAL', 'STEP',
          'ENABLE_SYNC_RST', 'ENABLE_ENABLE', 'RST_VAL', 'ENABLE_LOAD']
PARAM_DEFAULTS = {'ENABLE_LOAD': 0}


@cocotb.test()
async def module_test(dut):
    """Test counter module.

    Each clock cycle the simulated dout is read and compared against the
    expected value in simdata<N>/sim_dout.csv.

    Parameter sets:
        simdata0 : COUNTER_TYPE=0(free_running), COUNT_DIR=0(up),   NBITS=8, STEP=1, INIT_VAL=0,   COUNT_TO_VAL=0
        simdata1 : COUNTER_TYPE=0(free_running), COUNT_DIR=0(up),   NBITS=8, STEP=3, INIT_VAL=0,   COUNT_TO_VAL=0
        simdata2 : COUNTER_TYPE=0(free_running), COUNT_DIR=1(down), NBITS=8, STEP=1, INIT_VAL=255, COUNT_TO_VAL=0
        simdata3 : COUNTER_TYPE=1(count_limit),  COUNT_DIR=0(up),   NBITS=8, STEP=1, INIT_VAL=0,   COUNT_TO_VAL=20
        simdata4 : COUNTER_TYPE=1(count_limit),  COUNT_DIR=1(down), NBITS=8, STEP=1, INIT_VAL=20,  COUNT_TO_VAL=0
        simdata5-9 : RST_VAL / ENABLE_SYNC_RST / ENABLE_ENABLE sets, matched by
                     params.json; rst and enable driven from sim_rst/sim_enable.csv
        simdata10-13 : COUNT_DIR=2 (up port) / ENABLE_LOAD sets, matched by
                     params.json; load, din and up driven as well
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    nbits        = int(dut.NBITS.value)
    step         = int(dut.STEP.value)
    init_val     = int(dut.INIT_VAL.value)
    count_to_val = int(dut.COUNT_TO_VAL.value)
    counter_type = int(dut.COUNTER_TYPE.value)
    count_dir    = int(dut.COUNT_DIR.value)
    cocotb.log.info(
        f"Testing with NBITS={nbits}, STEP={step}, "
        f"INIT_VAL={init_val}, COUNT_TO_VAL={count_to_val}, "
        f"COUNTER_TYPE={counter_type}, COUNT_DIR={count_dir}"
    )

    datadir = find_data_dir(dut, testdatadir, PARAMS, PARAM_DEFAULTS)
    await run_driven(dut, datadir)


async def run_driven(dut, datadir):
    """Drive rst/enable (and load/din/up when present) from CSV before each
    edge, compare dout after it."""
    expected_results = np.loadtxt(datadir / "sim_dout.csv", dtype=int).tolist()
    inputs = {}
    for port in ["rst", "enable", "load", "din", "up"]:
        f = datadir / f"sim_{port}.csv"
        if f.exists():
            inputs[port] = np.loadtxt(f, dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(expected_results)} cycles from {datadir.name} "
                    f"(driving {', '.join(inputs)})")

    for i, expected in enumerate(expected_results):
        for port, vals in inputs.items():
            getattr(dut, port).value = vals[i]
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        drv = ", ".join(f"{port}={vals[i]}" for port, vals in inputs.items())
        assert actual == expected, (
            f"Cycle {i}: {drv}, expected dout={expected}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(expected_results)} cycles verified")
