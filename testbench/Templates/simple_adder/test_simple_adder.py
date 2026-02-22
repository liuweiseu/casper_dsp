import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

# testdir is used for getting the path for the input and output data file
testdir = Path(__file__).resolve().parent
# load the input and expected output data 
sim_a = np.loadtxt(testdir/'sim_a.csv', dtype=int).tolist()
sim_b = np.loadtxt(testdir/'sim_b.csv', dtype=int).tolist()
expected_results = np.loadtxt(testdir/'sim_sum.csv', dtype=int).tolist()

@cocotb.test()
async def simple_adder_test(dut):
    """
    test if 2 + 3 = 5
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    # initial values
    dut.a.value = 0
    dut.b.value = 0
    dut.rst.value = 1
    # release the reset in 10ns
    await Timer(10, units="ns")
    dut.rst.value = 0
    # set the input data
    for i in range(len(sim_a)):
        # input data should be prepared before the clk rising edge
        dut.a.value = sim_a[i]
        dut.b.value = sim_b[i]
        await RisingEdge(dut.clk)
        # output data should be sampled after the clk rising edge
        sum_val = int(dut.sum.value)
        assert sum_val == expected_results[i], f"Adder result is wrong: {sum_val} != {expected_results[i]}"
