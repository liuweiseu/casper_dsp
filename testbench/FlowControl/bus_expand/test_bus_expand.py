import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from pathlib import Path
import numpy as np

from testbench.csv_ports import load_rows

# testdatadir points to the corresponding test_data subdirectory
_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()

@cocotb.test()
async def module_test(dut):
    """test bus_create """
    nout = int(dut.OUTPUT_NUM.value)
    width = int(dut.OUTPUT_WIDTH.value)
    cocotb.log.info(f"Testing with OUTPUT_NUM={nout}, OUTPUT_WIDTH={width}")
    if nout == 4 and width == 8:
        # load the input and expected output data 
        sim_in = np.loadtxt(testdatadir/'simdata0/sim_bus_in.csv', dtype=int).tolist()
        # sim_bus_out<j>.csv = bus_out[j]; row i = [bus_out[0], ..., bus_out[OUTPUT_NUM-1]]
        sim_bus_out = np.array(load_rows(testdatadir/'simdata0', 'bus_out'))
        expected_results = [sim_bus_out[:, j].tolist() for j in range(nout)]
        for i in range(len(sim_in)):
            dut.bus_in.value = sim_in[i]
            # wait for the logic to be stable
            await Timer(1, units="ns")
            # get the output
            for j in range(nout):
                actual_output = dut.bus_out[j].value
                assert actual_output == expected_results[j][i], f"Output mismatch! Expected {hex(expected_results[j][i])}, got {hex(actual_output)}, index: {j}, {i}"
