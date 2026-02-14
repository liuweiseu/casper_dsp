# test_runner.py
import tomllib
import pytest
from cocotb_test.simulator import run
from pathlib import Path
import os

# read the toml file
with open("simulation.toml", "rb") as f:
    config = tomllib.load(f)["simulations"]

ids = [f"{c['dir']}/{c['top']}" for c in config]

@pytest.mark.parametrize("cfg", config, ids=ids)
def test_module(cfg):
    # get target
    target_dir = cfg["dir"]
    top = cfg["top"]
    # create sim build dir
    sim_build_path = Path(f"sim_results/{target_dir}/{top}")
    sim_build_path.mkdir(parents=True, exist_ok=True)
    # define the result files
    vcd_file = sim_build_path / f"{top}.vcd"
    results_xml = sim_build_path / "results.xml"
    os.environ["COCOTB_RESULTS_FILE"] = str(results_xml.absolute())
    # get the sources
    rtl_path = Path(f"../rtl/{target_dir}")
    sources = list(rtl_path.glob("*.v"))
    # start simulation
    run(
        verilog_sources=sources,
        toplevel=top,
        module=f"test_{top}",
        simulator="verilator",
        sim_build=sim_build_path,
        waves=True,
        compile_args=[
            "--trace", 
            "--trace-structs",
            "-Wno-fatal",
            "-DVM_TRACE=1"
        ],
        sim_args=[
            f"--trace-file={vcd_file.absolute()}"
        ]
)