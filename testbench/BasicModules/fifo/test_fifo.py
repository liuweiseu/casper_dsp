import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import numpy as np
from testbench.data_paths import find_data_dir, module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

PARAMS = ["DATA_WIDTH", "MEM_TYPE", "PERFORMANCE_OPTIONS", "EMBEDDED_REGISTERS", "DEPTH",
          "PERCENT_NBITS", "RST", "RST_LATENCY", "EN", "USE_DCOUNT", "USE_PERCENT_FULL_PORT",
          "USE_ALMOST_EMPTY", "ALMOST_EMPTY_THRESH", "USE_ALMOST_FULL", "ALMOST_FULL_THRESH"]


@cocotb.test()
async def module_test(dut):
    """Test the Xilinx FIFO block model.

    Drives din / we / re (and rst / en when their port is enabled) before each
    rising edge and compares every enabled output with simdata<N>/sim_<port>.csv
    after the edge. The CSVs were exported from Simulink; test_data.md lists the
    parameter sets.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    p = {name: int(getattr(dut, name).value) for name in PARAMS}
    cocotb.log.info("Testing with " + ", ".join(f"{k}={v}" for k, v in p.items()))
    datadir = find_data_dir(dut, testdatadir, PARAMS)

    def load(port):
        return np.loadtxt(datadir / f"sim_{port}.csv", dtype=int, ndmin=1).tolist()

    inputs = {port: load(port) for port in ("din", "we", "re")}
    if p["RST"]:
        inputs["rst"] = load("rst")
    if p["EN"]:
        inputs["en"] = load("en")

    outputs = ["dout", "empty", "full"]
    if p["USE_PERCENT_FULL_PORT"]:
        outputs.append("percent_full")
    if p["USE_DCOUNT"]:
        outputs.append("dcount")
    if p["USE_ALMOST_EMPTY"]:
        outputs.append("ae")
    if p["USE_ALMOST_FULL"]:
        outputs.append("af")
    expected = {port: load(port) for port in outputs}

    n = len(inputs["din"])
    for i in range(n):
        for port, vals in inputs.items():
            getattr(dut, port).value = vals[i]
        await RisingEdge(dut.clk)
        for port in outputs:
            actual = int(getattr(dut, port).value)
            exp = expected[port][i]
            assert actual == exp, (
                f"Index {i}: " + ", ".join(f"{k}={v[i]}" for k, v in inputs.items())
                + f" -> expected {port}={exp}, got {actual}"
            )

    cocotb.log.info(f"module_test PASSED — {n} cycles, outputs {', '.join(outputs)}")
