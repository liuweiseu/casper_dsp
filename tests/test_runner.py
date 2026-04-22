import tomllib
import pytest
from pathlib import Path
import os
import logging
from cocotb_tools.runner import get_runner
from prepare_dump import replace_vcd_filename, find_file

logger = logging.getLogger(__name__)

_PROJECT_ROOT = Path(__file__).parent.parent

PLATFORM_TO_VENDOR = {
    "XILINX": "xilinx",
    "ALTERA": "altera",
}

def get_vendor_sources(platform: str, vendor_cfgs: dict) -> list:
    key = PLATFORM_TO_VENDOR.get(platform.upper())
    if key is None:
        return []
    cfg = vendor_cfgs.get(key, {})
    lib_path = cfg.get("lib_path", "")
    if not lib_path:
        raise ValueError(f"No lib_path configured for platform: {platform}")
    path = Path(lib_path)
    resolved = ((_PROJECT_ROOT / path) if not path.is_absolute() else path).resolve()
    if not resolved.exists():
        raise FileNotFoundError(f"Vendor lib not found: {resolved}")
    return list(resolved.rglob("*.v")) + list(resolved.rglob("*.sv"))

# read the toml file
with open("simulation.toml", "rb") as f:
    full_config = tomllib.load(f)
    config      = full_config["simulations"]
    vendor_cfgs = {k: v for k, v in full_config.items()
                   if isinstance(v, dict) and k != "simulations"}

# generate id list
ids = [f"{c['dir']}/{c['top']}" for c in config]

@pytest.mark.parametrize("cfg", config, ids=ids)
def test_runner(cfg):
    target_dir = cfg.get('dir')
    top = cfg.get('top')
    parameters = cfg.get('parameters', [])
    
    sim = os.getenv("SIM", "verilator")
    result_path = Path("results")
    result_path.mkdir(parents=True, exist_ok=True)
    result_path = result_path.resolve()
    # get the sources
    rtl_path = Path(f"../rtl/")
    sources = list(rtl_path.rglob("*.v")) + list(rtl_path.rglob("*.sv"))
    
    # get the runner
    runner = get_runner(sim)

    # if no parameters are used, just build and test
    if len(parameters) == 0:
        # build the verilog modules
        top_result = result_path/f"{target_dir}/{top}/{top}.xml"
        top_result.parent.mkdir(parents=True, exist_ok=True)
        runner.build(
            sources=sources,
            hdl_toplevel=top,
            waves=True,
            defines={'SIM': ''},
            build_dir=f"sim_build/{target_dir}/{top}"
        )

        # run the tests
        runner.test(hdl_toplevel=top,
                    test_module=f"testbench.{target_dir}.{top}.test_{top},",
                    results_xml=top_result,
                    waves=True,
                    plusargs=['--trace --trace-structs']
                    )
    else:
        # if we have parameters, we need to run sim for all of these parameters
        for i in range(len(parameters)):
            top_result = result_path/f"{target_dir}/{top}/{top}_{i}.xml"
            top_result.parent.mkdir(parents=True, exist_ok=True)
            # 1. find the file
            fn = find_file(f'{top}.', '../rtl')
            logger.info(f'Found file names: {fn}')
            # 2. replace the vcd file name to the new one
            replace_vcd_filename(fn[0], f'{top}_{i}.vcd')
            # 3. build the verilog modules with the parameters
            platform = parameters[i].get("PLATFORM", "")
            extra = get_vendor_sources(platform, vendor_cfgs) if platform else []
            runner.build(
                sources=sources + extra,
                hdl_toplevel=top,
                waves=True,
                defines={'SIM': ''},
                parameters=parameters[i],
                build_dir=f"sim_build/{target_dir}/{top}"
            )
            # run the tests
            runner.test(hdl_toplevel=top,
                        test_module=f"testbench.{target_dir}.{top}.test_{top},",
                        results_xml=top_result,
                        waves=True,
                        plusargs=['--trace --trace-structs']
                        )