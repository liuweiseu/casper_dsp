import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import numpy as np
from testbench.data_paths import module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

@cocotb.test()
async def module_test(dut):
    """test bus_create """
    start_bit = int(dut.START_BIT.value)
    width = int(dut.WIDTH.value)
    cocotb.log.info(f"Testing with START_BIT={start_bit}, WIDTH={width}")
    if start_bit == 0 and width == 2:
        # test START_BIT = 0 and width = 2
        # load the input and expected output data 
        sim_in = np.loadtxt(testdatadir/'sim_din.csv', dtype=int).tolist()
        expected_results = np.loadtxt(testdatadir/'sim_dout.csv', dtype=int).tolist()
        for i in range(len(sim_in)):
            dut.din.value = sim_in[i]
            # wait for the logic to be stable
            await Timer(1, units="ns")
            # get the output
            actual_output = dut.dout.value
            assert actual_output == expected_results[i], f"Output mismatch! Expected {hex(expected_results[i])}, got {hex(actual_output)}, index: {i}"
