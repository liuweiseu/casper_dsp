import json

import cocotb
from cocotb.triggers import Timer

from testbench.data_paths import module_data_dir

# test data of this module: $CASPER_TEST_DATA or test_data/, same path as below testbench/
testdatadir = module_data_dir(__file__)


def pack(values):
    """mask vector -> packed parameter value (32-bit elements, first in the MSBs)"""
    v = 0
    for x in values:
        v = (v << 32) | (x & 0xFFFFFFFF)
    return v


def load(path):
    # din / dout can be wider than 64 bits: parse as Python ints
    return [int(line) for line in path.read_text().split()]


@cocotb.test()
async def module_test(dut):
    """Test munge (combinational).

    Selects the simdata<N> whose params.json (DIV_SIZE / ORDER as mask
    vectors) matches the DUT, drives din from sim_din.csv and compares dout
    with sim_dout.csv. The CSVs were exported from Simulink.
    """
    dut_params = {"DIVISIONS": int(dut.DIVISIONS.value),
                  "DIV_SIZE": int(dut.DIV_SIZE.value), "ORDER": int(dut.ORDER.value)}
    datadir = None
    for d in sorted(testdatadir.glob("simdata*")):
        p = json.loads((d / "params.json").read_text())
        if {"DIVISIONS": p["DIVISIONS"], "DIV_SIZE": pack(p["DIV_SIZE"]), "ORDER": pack(p["ORDER"])} == dut_params:
            datadir, params = d, p
            break
    assert datadir is not None, f"no simdataN/params.json in {testdatadir} matches {dut_params}"
    cocotb.log.info(f"Testing with {params} ({datadir.name})")

    sim_din = load(datadir / "sim_din.csv")
    sim_dout = load(datadir / "sim_dout.csv")
    for i in range(len(sim_din)):
        dut.din.value = sim_din[i]
        await Timer(1, units="ns")
        actual = int(dut.dout.value)
        assert actual == sim_dout[i], f"Index {i}: din={sim_din[i]:#x} -> expected dout={sim_dout[i]:#x}, got {actual:#x}"

    cocotb.log.info(f"module_test PASSED — {len(sim_din)} samples")
