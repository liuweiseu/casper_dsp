import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def adder_basic_test(dut):
    """
    test if 2 + 3 = 5
    """

    dut.a.value = 2
    dut.b.value = 3

    await Timer(10, units="ns")

    sum_val = int(dut.sum.value)
    print(f"Result: {dut.a.value} + {dut.b.value} = {sum_val}")
    
    assert sum_val == 5, f"Adder result is wrong: {sum_val} != 5"
