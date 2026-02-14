import tomllib
import pytest
from pathlib import Path
import os
from cocotb_tools.runner import get_runner

# read the toml file
with open("simulation.toml", "rb") as f:
    config = tomllib.load(f)["simulations"]

# generate id list
ids = [f"{c['dir']}/{c['top']}" for c in config]

@pytest.mark.parametrize("cfg", config, ids=ids)
def test_runner(cfg):
    target_dir = cfg["dir"]
    top = cfg["top"]
    sim = os.getenv("SIM", "verilator")
    result_path = Path("results")
    result_path.mkdir(parents=True, exist_ok=True)
    result_path = result_path.resolve()
    top_result = result_path/f"{target_dir}/{top}/{top}.xml"
    top_result.parent.mkdir(parents=True, exist_ok=True)
    # get the sources
    rtl_path = Path(f"../rtl/{target_dir}")
    sources = list(rtl_path.glob("*.v"))

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=top,
        waves=True,
        build_dir=f"sim_build/{target_dir}/{top}"
    )
    runner.test(hdl_toplevel=top,
                test_module=f"testbench.test_{top},",
                results_xml=top_result,
                waves=True,
                plusargs=['--trace --trace-structs']
                )