import tomllib
import pytest
from pathlib import Path
import os, sys
from cocotb_tools.runner import get_runner

# read the toml file
with open("simulation.toml", "rb") as f:
    config = tomllib.load(f)["simulations"]

# generate id list
ids = [f"{c['dir']}/{c['top']}" for c in config]

@pytest.mark.parametrize("cfg", config, ids=ids)
def test_runner(cfg):
    target_dir = cfg.get('dir')
    top = cfg.get('top')
    parameters = cfg.get('parameters', {})

    sim = os.getenv("SIM", "verilator")
    result_path = Path("results")
    result_path.mkdir(parents=True, exist_ok=True)
    result_path = result_path.resolve()
    top_result = result_path/f"{target_dir}/{top}/{top}.xml"
    top_result.parent.mkdir(parents=True, exist_ok=True)
    # get the sources
    rtl_path = Path(f"../rtl/")
    sources = list(rtl_path.rglob("*.v")) + list(rtl_path.rglob("*.sv"))
    
    # get the runner
    runner = get_runner(sim)
    # build the verilog modules
    runner.build(
        sources=sources,
        hdl_toplevel=top,
        waves=True,
        defines={'SIM': ''},
        parameters = parameters,
        build_dir=f"sim_build/{target_dir}/{top}"
    )
    # run the tests
    runner.test(hdl_toplevel=top,
                test_module=f"testbench.{target_dir}.{top}.test_{top},",
                results_xml=top_result,
                waves=True,
                plusargs=['--trace --trace-structs']
                )