import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from testbench.data_paths import find_data_dir, module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

PARAMS = ["BIT_WIDTH", "ADD_LATENCY", "MULT_LATENCY"]


def load(path):
    return [int(v) for v in path.read_text().split()]


@cocotb.test()
async def module_test(dut):
    """Test power: |c|^2 against the Simulink export (simdataN/sim_c.csv, sim_dout.csv)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    datadir = find_data_dir(dut, testdatadir, PARAMS)
    cocotb.log.info(f"Testing {datadir.name}: " + ", ".join(f"{p}={int(getattr(dut, p).value)}" for p in PARAMS))
    sim_c = load(datadir / "sim_c.csv")
    sim_dout = load(datadir / "sim_dout.csv")

    for i in range(len(sim_c)):
        dut.c.value = sim_c[i]
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == sim_dout[i], f"Index {i}: c={sim_c[i]:#x} -> expected dout={sim_dout[i]:#x}, got {actual:#x}"

    cocotb.log.info(f"module_test PASSED — {len(sim_c)} cycles")
