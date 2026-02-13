import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def adder_basic_test(dut):
    """测试 2 + 3 是否等于 5"""

    # 输入数据
    dut.a.value = 2
    dut.b.value = 3

    # 等待 10ns 让组合逻辑稳定
    await Timer(10, units="ns")

    # 获取结果并断言
    sum_val = int(dut.sum.value)
    print(f"Result: {dut.a.value} + {dut.b.value} = {sum_val}")
    
    assert sum_val == 5, f"Adder result is wrong: {sum_val} != 5"
