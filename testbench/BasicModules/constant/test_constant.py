import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def module_test(dut):
    """Test constant module.

    Waits one nanosecond for combinational output to settle, then verifies
    that out equals VAL truncated to NBITS.

    No CSV test data is needed: the expected value is derived directly from
    the DUT parameters NBITS and VAL.
    """
    await Timer(1, units="ns")

    nbits    = int(dut.NBITS.value)
    val      = int(dut.VAL.value)
    expected = val & ((1 << nbits) - 1)
    actual   = int(dut.out.value)

    assert actual == expected, (
        f"NBITS={nbits}, VAL={val}: expected out={expected}, got {actual}"
    )

    cocotb.log.info(
        f"module_test PASSED — NBITS={nbits}, VAL={val}, out={actual}"
    )
