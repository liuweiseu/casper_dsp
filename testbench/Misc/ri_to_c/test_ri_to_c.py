import cocotb
from cocotb.triggers import Timer

from pathlib import Path
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


@cocotb.test()
async def module_test(dut):
    """Test ri_to_c module.

    Drive re and im inputs with values from sim_in_re.csv / sim_in_im.csv and
    verify that the packed output c == {re, im} matches sim_out.csv.

    Parameter sets:
        simdata0 : NBITS=8  — pack two 8-bit words into 16-bit complex
        simdata1 : NBITS=16 — pack two 16-bit words into 32-bit complex
    """
    nbits = int(dut.NBITS.value)
    cocotb.log.info(f"Testing with NBITS={nbits}")

    if nbits == 8:
        datadir = testdatadir / "simdata0"
    elif nbits == 16:
        datadir = testdatadir / "simdata1"
    else:
        cocotb.log.warning(f"No test data for NBITS={nbits}. Skipping.")
        return

    sim_in_re = np.loadtxt(datadir / "sim_in_re.csv", dtype=int).tolist()
    sim_in_im = np.loadtxt(datadir / "sim_in_im.csv", dtype=int).tolist()
    expected  = np.loadtxt(datadir / "sim_out.csv",   dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(sim_in_re)} samples from {datadir.name}/")

    for i, (re_val, im_val, exp) in enumerate(zip(sim_in_re, sim_in_im, expected)):
        dut.re.value = re_val
        dut.im.value = im_val
        await Timer(1, units="ns")
        actual = int(dut.c.value)
        assert actual == exp, (
            f"Index {i}: re={hex(re_val)} im={hex(im_val)} "
            f"expected c={hex(exp)}, got {hex(actual)}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_in_re)} samples verified")
