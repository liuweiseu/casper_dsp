import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

# testdir is used for getting the path for the input and output data file
testdir = Path(__file__).resolve().parent

@cocotb.test()
async def bus_create_test_0(dut):
    """test bus_create """
    start_bit = int(dut.START_BIT.value)
    width = int(dut.WIDTH.value)
    cocotb.log.info(f"Testing with START_BIT={start_bit}, WIDTH={width}")
    if start_bit == 0 and width == 2:
        # test START_BIT = 0 and width = 2
        # load the input and expected output data 
        sim_in = np.loadtxt(testdir/'sim_in.csv', dtype=int).tolist()
        expected_results = np.loadtxt(testdir/'sim_out.csv', dtype=int).tolist()
        for i in range(len(sim_in)):
            dut.din.value = sim_in[i]
            # wait for the logic to be stable
            await Timer(1, units="ns")
            # get the output
            actual_output = dut.dout.value
            assert actual_output == expected_results[i], f"Output mismatch! Expected {hex(expected_results[i])}, got {hex(actual_output)}, index: {i}"
