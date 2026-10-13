import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

import numpy as np

from testbench.csv_ports import load_rows
from testbench.data_paths import find_data_dir, module_data_dir

testdatadir = module_data_dir(__file__)


# Parameters matched against simdataN/params.json
PARAMS = ['NBITS', 'NINPUTS', 'LATENCY', 'FUNC', 'USE_ENABLE']


AND  = 0
NAND = 1
OR   = 2
NOR  = 3
XOR  = 4
XNOR = 5


@cocotb.test()
async def module_test(dut):
    """Test logical module.

    sim_dout[i] = dout value before clock edge i (pre-edge read convention).
    Initial shift_reg = 0, so sim_dout[0..LATENCY-1] = 0.

    Parameter sets:
        simdata0 : FUNC=0(AND),  NBITS=4, NINPUTS=2, LATENCY=1
        simdata1 : FUNC=1(NAND), NBITS=4, NINPUTS=2, LATENCY=1
        simdata2 : FUNC=2(OR),   NBITS=4, NINPUTS=2, LATENCY=1
        simdata3 : FUNC=3(NOR),  NBITS=4, NINPUTS=2, LATENCY=1
        simdata4 : FUNC=4(XOR),  NBITS=4, NINPUTS=2, LATENCY=1
        simdata5 : FUNC=5(XNOR), NBITS=4, NINPUTS=2, LATENCY=1
        simdata6 : FUNC=0(AND),  NBITS=4, NINPUTS=3, LATENCY=1
        simdata7 : FUNC=4(XOR),  NBITS=4, NINPUTS=2, LATENCY=2
        simdata8 : FUNC=2(OR),   NBITS=4, NINPUTS=3, LATENCY=2, USE_ENABLE=1
                   (en driven from sim_en.csv)
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    nbits   = int(dut.NBITS.value)
    ninputs = int(dut.NINPUTS.value)
    latency = int(dut.LATENCY.value)
    func    = int(dut.FUNC.value)

    cocotb.log.info(
        f"Testing with NBITS={nbits}, NINPUTS={ninputs}, "
        f"LATENCY={latency}, FUNC={func}"
    )

    datadir = find_data_dir(dut, testdatadir, PARAMS)

    # sim_din<j>.csv = din[j]; row i = [din[0], ..., din[NINPUTS-1]]
    sim_din  = load_rows(datadir, "din")
    expected = np.loadtxt(datadir / "sim_dout.csv", dtype=int).tolist()
    en_file  = datadir / "sim_en.csv"
    sim_en   = np.loadtxt(en_file, dtype=int).tolist() if en_file.exists() else None

    cocotb.log.info(f"Loaded {len(expected)} expected values from {datadir.name}")

    for i in range(len(expected)):
        # cocotb/Verilator unpacked-array convention: list[k] -> din[k]
        dut.din.value = sim_din[i]
        if sim_en is not None:
            dut.en.value = sim_en[i]
        await RisingEdge(dut.clk)
        actual = int(dut.dout.value)
        assert actual == expected[i], (
            f"Index {i}: din={sim_din[i]} "
            f"→ expected dout={expected[i]}, got {actual}"
        )

    cocotb.log.info(f"module_test PASSED — {len(expected)} cycles verified")
