import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

# testdir is used for getting the path for the input and output data file
testdir = Path(__file__).resolve().parent
# load the input and expected output data 
sim_in1 = np.loadtxt(testdir/'simdata0/sim_in1.csv', dtype=int).tolist()
sim_in2 = np.loadtxt(testdir/'simdata0/sim_in2.csv', dtype=int).tolist()
expected_results = np.loadtxt(testdir/'simdata0/sim_out.csv', dtype=int).tolist()

param_sets = [
    {"NBITS": 8, "NINPUTS": 2},
]
for params in param_sets:
    @cocotb.test()
    async def bus_create_test(dut, params=params):
        """test bus_create """
        nbits = int(dut.NBITS.value)
        ninputs = int(dut.NINPUTS.value)
        
        cocotb.log.info(f"Testing with NBITS={nbits}, NINPUTS={ninputs}")

        for i in range(len(sim_in1)):
            dut.din.value = [sim_in2[i], sim_in1[i]]
            # wait for the logic to be stable
            await Timer(1, units="ns")
            # get the output
            actual_output = dut.bus_out.value
            cocotb.log.info(f"index: {i}")
            cocotb.log.info(f"Expected: {hex(expected_results[i])}")
            cocotb.log.info(f"Actual:   {hex(actual_output)}")

            assert actual_output == expected_results[i], f"Output mismatch! Expected {hex(expected_results[i])}, got {hex(actual_output)}"
