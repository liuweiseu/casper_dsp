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
    """Test bus_expand module.

    Drives bus_in with values from sim_in.csv and verifies that each
    bus_out[j] matches the corresponding sim_out{j+1}.csv slice.

    Parameter sets:
        simdata0 : NOUT=4, WIDTH=8 — equal-size, 4 × 8-bit outputs
    """
    nout = int(dut.NOUT.value)
    width = int(dut.WIDTH.value)
    cocotb.log.info(f"Testing with NOUT={nout}, WIDTH={width}")
    if nout == 4 and width == 8:
        # load the input and expected output data 
        sim_in = np.loadtxt(testdatadir/'simdata0/sim_in.csv', dtype=int).tolist()
        expected_results = np.zeros(nout, dtype=object)
        expected_results[0] = np.loadtxt(testdatadir/'simdata0/sim_out1.csv', dtype=int).tolist()
        expected_results[1] = np.loadtxt(testdatadir/'simdata0/sim_out2.csv', dtype=int).tolist()
        expected_results[2] = np.loadtxt(testdatadir/'simdata0/sim_out3.csv', dtype=int).tolist()
        expected_results[3] = np.loadtxt(testdatadir/'simdata0/sim_out4.csv', dtype=int).tolist()
        for i in range(len(sim_in)):
            dut.bus_in.value = sim_in[i]
            # wait for the logic to be stable
            await Timer(1, units="ns")
            # get the output
            for j in range(nout):
                actual_output = dut.bus_out[j].value
                assert actual_output == expected_results[j][i], f"Output mismatch! Expected {hex(expected_results[j][i])}, got {hex(actual_output)}, index: {j}, {i}"
