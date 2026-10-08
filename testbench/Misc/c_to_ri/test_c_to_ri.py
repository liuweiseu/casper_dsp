import cocotb
from cocotb.triggers import Timer

from pathlib import Path
import numpy as np

_here = Path(__file__).parent
testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()


@cocotb.test()
async def module_test(dut):
    """Test c_to_ri module.

    Drive the packed complex input c with values from sim_c.csv and verify
    that re and im outputs match sim_re.csv and sim_im.csv.

    Parameter sets:
        simdata0 : N_BITS=8,  BIN_PT=7  — unpack 16-bit complex into two 8-bit parts
        simdata1 : N_BITS=16, BIN_PT=15 — unpack 32-bit complex into two 16-bit parts
    """
    nbits  = int(dut.N_BITS.value)
    bin_pt = int(dut.BIN_PT.value)
    cocotb.log.info(f"Testing with N_BITS={nbits}, BIN_PT={bin_pt}")

    if nbits == 8:
        datadir = testdatadir / "simdata0"
    elif nbits == 16:
        datadir = testdatadir / "simdata1"
    else:
        cocotb.log.warning(f"No test data for N_BITS={nbits}. Skipping.")
        return

    sim_in = np.loadtxt(datadir / "sim_c.csv",     dtype=int).tolist()
    exp_re = np.loadtxt(datadir / "sim_re.csv", dtype=int).tolist()
    exp_im = np.loadtxt(datadir / "sim_im.csv", dtype=int).tolist()
    cocotb.log.info(f"Loaded {len(sim_in)} samples from {datadir.name}/")

    for i, (c_val, e_re, e_im) in enumerate(zip(sim_in, exp_re, exp_im)):
        dut.c.value = c_val
        await Timer(1, units="ns")
        actual_re = int(dut.re.value)
        actual_im = int(dut.im.value)
        assert actual_re == e_re, (
            f"Index {i}: c={hex(c_val)} expected re={hex(e_re)}, got {hex(actual_re)}"
        )
        assert actual_im == e_im, (
            f"Index {i}: c={hex(c_val)} expected im={hex(e_im)}, got {hex(actual_im)}"
        )

    cocotb.log.info(f"module_test PASSED — {len(sim_in)} samples verified")
