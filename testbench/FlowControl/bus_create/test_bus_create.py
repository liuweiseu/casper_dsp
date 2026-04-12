import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

# testdatadir points to the corresponding test_data subdirectory
_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

@cocotb.test()
async def module_test(dut):
    """test bus_create """
    nbits = int(dut.NBITS.value)
    ninputs = int(dut.NINPUTS.value)
    cocotb.log.info(f"Testing with NBITS={nbits}, NINPUTS={ninputs}")
    if nbits == 8 and ninputs == 2:
        # test NBITS = 8 and NINPUTS = 2
        # load the input and expected output data 
        sim_in1 = np.loadtxt(testdatadir/'simdata0/sim_in1.csv', dtype=int).tolist()
        sim_in2 = np.loadtxt(testdatadir/'simdata0/sim_in2.csv', dtype=int).tolist()
        expected_results = np.loadtxt(testdatadir/'simdata0/sim_out.csv', dtype=int).tolist()
        for i in range(len(sim_in1)):
            dut.din.value = [sim_in2[i], sim_in1[i]]
            # wait for the logic to be stable
            await Timer(1, units="ns")
            # get the output
            actual_output = dut.bus_out.value
            assert actual_output == expected_results[i], f"Output mismatch! Expected {hex(expected_results[i])}, got {hex(actual_output)}"
    elif nbits == 10 and ninputs == 4:
        # test NBITS = 10 and NINPUTS = 4
        # load the input and expected output data 
        sim_in1 = np.loadtxt(testdatadir/'simdata1/sim_in1.csv', dtype=int).tolist()
        sim_in2 = np.loadtxt(testdatadir/'simdata1/sim_in2.csv', dtype=int).tolist()
        sim_in3 = np.loadtxt(testdatadir/'simdata1/sim_in3.csv', dtype=int).tolist()
        sim_in4 = np.loadtxt(testdatadir/'simdata1/sim_in4.csv', dtype=int).tolist()
        expected_results = np.loadtxt(testdatadir/'simdata1/sim_out.csv', dtype=np.int64).tolist()
        for i in range(len(sim_in1)):
            dut.din.value = [sim_in4[i], sim_in3[i], sim_in2[i], sim_in1[i]]
            # wait for the logic to be stable
            await Timer(1, units="ns")
            # get the output
            actual_output = dut.bus_out.value
            assert actual_output == expected_results[i], f"Output mismatch! Expected {hex(expected_results[i])}, got {hex(actual_output)}"
