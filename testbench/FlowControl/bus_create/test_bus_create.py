import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import numpy as np

from testbench.csv_ports import load_rows
from testbench.data_paths import find_data_dir, module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)

@cocotb.test()
async def module_test(dut):
    """test bus_create """
    nbits = int(dut.NBITS.value)
    ninputs = int(dut.INPUT_NUM.value)
    cocotb.log.info(f"Testing with NBITS={nbits}, INPUT_NUM={ninputs}")
    datadir = find_data_dir(dut, testdatadir, ["NBITS", "INPUT_NUM"])
    # load the input and expected output data
    # sim_din<j>.csv = din[j]; row i = [din[0], ..., din[INPUT_NUM-1]]
    sim_din = load_rows(datadir, 'din')
    expected_results = np.loadtxt(datadir/'sim_bus_out.csv', dtype=np.int64).tolist()
    for i in range(len(sim_din)):
        dut.din.value = sim_din[i]
        # wait for the logic to be stable
        await Timer(1, units="ns")
        # get the output
        actual_output = dut.bus_out.value
        assert actual_output == expected_results[i], f"Output mismatch! Expected {hex(expected_results[i])}, got {hex(actual_output)}"
