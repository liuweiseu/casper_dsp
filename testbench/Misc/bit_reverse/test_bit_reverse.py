import cocotb
from cocotb.triggers import Timer

from pathlib import Path
import numpy as np

# testdatadir points to the corresponding test_data subdirectory
_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


@cocotb.test()
async def module_test(dut):
    """Test bit_reverse module.

    For each input value in sim_din.csv, drive din and compare dout against
    the expected bit-reversed value in sim_dout.csv.

    Parameter sets:
        simdata0 : N_BITS=8,  all 256 input values (0 to 255)
        simdata1 : N_BITS=16, 300 random input values
    """
    nbits = int(dut.N_BITS.value)
    cocotb.log.info(f"Testing with N_BITS={nbits}")

    if nbits == 8:
        datadir = testdatadir / "simdata0"
    elif nbits == 16:
        datadir = testdatadir / "simdata1"
    else:
        cocotb.log.warning(f"No test data for N_BITS={nbits}. Skipping.")
        return

    sim_in          = np.loadtxt(datadir / "sim_din.csv",  dtype=int).tolist()
    expected_results = np.loadtxt(datadir / "sim_dout.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(sim_in)} values from {datadir.name}/")

    for i, (din_val, expected) in enumerate(zip(sim_in, expected_results)):
        dut.din.value = din_val
        await Timer(1, units="ns")
        actual = int(dut.dout.value)
        assert actual == expected, (
            f"Index {i}: din={din_val} ({hex(din_val)}), "
            f"expected dout={expected} ({hex(expected)}), "
            f"got {actual} ({hex(actual)})"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_in)} values verified")
