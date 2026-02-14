import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from pathlib import Path
# testdir is used for getting the path for the input and output data file
testdir = Path(__file__).resolve().parent

@cocotb.test()
async def simple_adder_test(dut):
    """
    test if 2 + 3 = 5
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.a.value = 2
    dut.b.value = 3

    dut.rst.value = 1
    await Timer(20, units="ns")
    dut.rst.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    sum_val = int(dut.sum.value)
    print(f"Result: {dut.a.value} + {dut.b.value} = {sum_val}")
    
    assert sum_val == 5, f"Adder result is wrong: {sum_val} != 5"
