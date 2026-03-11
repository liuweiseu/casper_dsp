import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

# testdir is used for getting the path for the input and output data file
testdir = Path(__file__).resolve().parent

@cocotb.test()
async def module_test(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    """test bus_create """
    latency = int(dut.LATENCY.value)
    bitwidth = int(dut.BITWIDTH.value)
    cocotb.log.info(f"Testing with LATENCY={latency}, BITWIDTH={bitwidth}")
    if latency == 1 and bitwidth == 3:
        # test LATENCY = 0 and BITWIDTH = 3
        # load the input and expected output data 
        sim_in = np.loadtxt(testdir/'sim_in.csv', dtype=int).tolist()
        expected_results = np.loadtxt(testdir/'sim_out.csv', dtype=int).tolist()
        for i in range(len(sim_in)):
            dut.din.value = sim_in[i]
            # wait for the logic to be stable
            await RisingEdge(dut.clk)
            # get the output
            actual_output = int(dut.dout.value)
            assert actual_output == expected_results[i], f"Output mismatch! Expected {hex(expected_results[i])}, got {hex(actual_output)}, index: {i}"
