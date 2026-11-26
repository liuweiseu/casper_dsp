import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from testbench.data_paths import find_data_dir, module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

PARAMS = ["VEC_LEN", "ARITH_TYPE", "N_BITS", "BIN_PT", "N_BITS_IN", "BIN_PT_IN", "TYPE_IN"]


def load(path):
    # dout can be 64 bits wide: parse as Python ints
    return [int(v) for v in path.read_text().split()]


@cocotb.test()
async def module_test(dut):
    """Test simple_bram_vacc against the Simulink export (new_acc, din -> dout, valid)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    datadir = find_data_dir(dut, testdatadir, PARAMS)
    cocotb.log.info(f"Testing {datadir.name}: " + ", ".join(f"{p}={int(getattr(dut, p).value)}" for p in PARAMS))
    new_acc = load(datadir / "sim_new_acc.csv")
    din = load(datadir / "sim_din.csv")
    expected = {"dout": load(datadir / "sim_dout.csv"), "valid": load(datadir / "sim_valid.csv")}

    for i in range(len(din)):
        dut.new_acc.value = new_acc[i]
        dut.din.value = din[i]
        await RisingEdge(dut.clk)
        for port, exp in expected.items():
            actual = int(getattr(dut, port).value)
            assert actual == exp[i], (f"Index {i}: new_acc={new_acc[i]} din={din[i]:#x} -> "
                                      f"expected {port}={exp[i]:#x}, got {actual:#x}")

    cocotb.log.info(f"module_test PASSED — {len(din)} cycles")
