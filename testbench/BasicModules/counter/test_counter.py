import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from pathlib import Path
import numpy as np

# testdatadir points to the corresponding test_data subdirectory
_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

# Must match localparam values in counter.sv
FREE_RUNNING = 0
COUNT_LIMIT  = 1
DIR_UP       = 0
DIR_DOWN     = 1


@cocotb.test()
async def module_test(dut):
    """Test counter module.

    Each clock cycle the simulated dout is read and compared against the
    expected value in simdata<N>/sim_out.csv.

    Parameter sets:
        simdata0 : COUNTER_TYPE=0(free_running), COUNT_DIR=0(up),   NBITS=8, STEP=1, INIT_VAL=0,   COUNT_TO_VAL=0
        simdata1 : COUNTER_TYPE=0(free_running), COUNT_DIR=0(up),   NBITS=8, STEP=3, INIT_VAL=0,   COUNT_TO_VAL=0
        simdata2 : COUNTER_TYPE=0(free_running), COUNT_DIR=1(down), NBITS=8, STEP=1, INIT_VAL=255, COUNT_TO_VAL=0
        simdata3 : COUNTER_TYPE=1(count_limit),  COUNT_DIR=0(up),   NBITS=8, STEP=1, INIT_VAL=0,   COUNT_TO_VAL=20
        simdata4 : COUNTER_TYPE=1(count_limit),  COUNT_DIR=1(down), NBITS=8, STEP=1, INIT_VAL=20,  COUNT_TO_VAL=0
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

    if   counter_type == FREE_RUNNING and count_dir == DIR_UP   and step == 1 and init_val == 0   and count_to_val == 0:
        datadir = testdatadir / "simdata0"   # free_running, up, step=1
    elif counter_type == FREE_RUNNING and count_dir == DIR_UP   and step == 3 and init_val == 0   and count_to_val == 0:
        datadir = testdatadir / "simdata1"   # free_running, up, step=3
    elif counter_type == FREE_RUNNING and count_dir == DIR_DOWN and step == 1 and init_val == 255 and count_to_val == 0:
        datadir = testdatadir / "simdata2"   # free_running, down, step=1
    elif counter_type == COUNT_LIMIT  and count_dir == DIR_UP   and step == 1 and init_val == 0   and count_to_val == 20:
        datadir = testdatadir / "simdata3"   # count_limit, up
    elif counter_type == COUNT_LIMIT  and count_dir == DIR_DOWN and step == 1 and init_val == 20  and count_to_val == 0:
        datadir = testdatadir / "simdata4"   # count_limit, down
    else:
        cocotb.log.warning(
            f"No test data for COUNTER_TYPE={counter_type}, COUNT_DIR={count_dir}, "
            f"STEP={step}, INIT_VAL={init_val}, COUNT_TO_VAL={count_to_val}. Skipping."
        )
        return

    expected_results = np.loadtxt(datadir / "sim_out.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(expected_results)} expected values from {datadir.name}/sim_out.csv")

    for i, expected in enumerate(expected_results):
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == expected, (
            f"Cycle {i}: expected dout={expected} ({hex(expected)}), "
            f"got {actual} ({hex(actual)})"
        )

    cocotb.log.info(f"module_test PASSED — {len(expected_results)} cycles verified")
