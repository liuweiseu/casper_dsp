import tomllib
import pytest
from pathlib import Path
import os
import subprocess
import sys
import logging
import re
from cocotb_tools.runner import get_runner
from prepare_dump import replace_vcd_filename, find_file
from testbench.data_paths import TEST_DATA_ENV, test_data_root

logger = logging.getLogger(__name__)

_PROJECT_ROOT = Path(__file__).parent.parent
# test data generators (test_data/scripts/); in the test container test_data/
# is copied next to this file, in a checkout it is one level up
_TEST_DATA_SCRIPTS = next((p / "test_data" / "scripts"
                           for p in (Path(__file__).parent, _PROJECT_ROOT)
                           if (p / "test_data" / "scripts").is_dir()), None)

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

# ── simulation config and test data location ────────────────────────────────
# CASPER_SIM_CONFIG: the simulation config file to use (default:
# simulation.toml next to this file). CASPER_TEST_DATA: a test data root laid
# out exactly like test_data/ (default: test_data/ next to testbench/, see
# testbench/data_paths.py). scripts/run-*.sh set both inside the container
# from their --config / --test-data options or the host environment.
SIM_CONFIG_ENV = "CASPER_SIM_CONFIG"
SIM_CONFIG = Path(os.environ.get(SIM_CONFIG_ENV) or Path(__file__).parent / "simulation.toml").resolve()
TEST_DATA_OVERRIDE = bool(os.environ.get(TEST_DATA_ENV))
TEST_DATA_ROOT = test_data_root()
if not SIM_CONFIG.is_file():
    raise FileNotFoundError(f"simulation config not found: {SIM_CONFIG}"
                            + (f" (from {SIM_CONFIG_ENV})" if os.environ.get(SIM_CONFIG_ENV) else ""))
if not TEST_DATA_ROOT.is_dir():
    raise FileNotFoundError(f"test data directory not found: {TEST_DATA_ROOT}"
                            + (f" (from {TEST_DATA_ENV})" if TEST_DATA_OVERRIDE else ""))

# parameters naming memory files are written relative to the build directory
# (sim_build/<dir>/<top>/), e.g. "../../../test_data/FFTs/...": with an
# external test data root they are redirected to it (absolute path)
_REL_TEST_DATA = re.compile(r"^(?:\.\./)+test_data/")


def test_data_param(value):
    if TEST_DATA_OVERRIDE and isinstance(value, str) and _REL_TEST_DATA.match(value):
        return f"{TEST_DATA_ROOT}/{_REL_TEST_DATA.sub('', value)}"
    return value


test_data_param.__test__ = False   # a helper, not a pytest test


def vector_param(values):
    """[a, b, ...] -> "<32n>'h<a><b>...": 32-bit elements, first in the MSBs
    (the SystemVerilog {32'd a, 32'd b, ...})."""
    return f"{32 * len(values)}'h" + "".join(f"{v & 0xFFFFFFFF:08x}" for v in values)


def check_test_data(cfg):
    """Fail early if the module's test data does not match its config entry.

    The module needs <root>/<dir>/<top>/; if that holds simdataN/
    subdirectories they must be simdata0 .. simdata<n-1>, one per
    [[simulations.parameters]] block (n = 1 for an entry without blocks).
    """
    d = TEST_DATA_ROOT / cfg["dir"] / cfg["top"]
    if not d.is_dir():
        pytest.fail(f"test data directory missing: {d}")
    sims = sorted(int(p.name[7:]) for p in d.iterdir()
                  if p.is_dir() and re.fullmatch(r"simdata\d+", p.name))
    n_sets = max(1, len(cfg.get("parameters", [])))
    if sims and sims != list(range(n_sets)):
        pytest.fail(f"{d}: has simdata{sims} but {SIM_CONFIG.name} lists {n_sets} "
                    f"parameter set(s) for {cfg['dir']}/{cfg['top']} (expected simdata0..{n_sets - 1})")


check_test_data.__test__ = False

# read the toml file
with open(SIM_CONFIG, "rb") as f:
    try:
        full_config = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        raise ValueError(f"{SIM_CONFIG}: {e}") from e
    config      = full_config["simulations"]
    vendor_cfgs = {k: v for k, v in full_config.items()
                   if isinstance(v, dict) and k not in ("simulations", "test_data")}
    # [test_data] generate: regenerate test data with the generator scripts
    # before the tests (see the comments in simulation.toml)
    generate_default = bool(full_config.get("test_data", {}).get("generate", False))


def generate_test_data(cfg):
    """Regenerate this module's test data if simulation.toml asks for it.

    Uses the entry's test_data_script with --module <top>, so only this
    module's data is rewritten. Entries without a script keep their data.
    """
    top = cfg["top"]
    if not cfg.get("generate_test_data", generate_default):
        return
    script = cfg.get("test_data_script")
    if not script:
        logger.info(f"{cfg['dir']}/{top}: no test_data_script, using existing test data")
        return
    if TEST_DATA_OVERRIDE:
        # the generators write into the default test_data/, never into the
        # external (read-only) directory the tests would read
        raise RuntimeError(f"{cfg['dir']}/{top}: test data generation is enabled, but "
                           f"{TEST_DATA_ENV} points to external test data ({TEST_DATA_ROOT}); "
                           "set generate = false (or generate_test_data = false) in "
                           f"{SIM_CONFIG.name}, or drop the external test data")
    if _TEST_DATA_SCRIPTS is None:
        raise FileNotFoundError("test_data/scripts/ not found, cannot generate test data")
    path = _TEST_DATA_SCRIPTS / script
    logger.warning(f"{cfg['dir']}/{top}: generating test data with {script}")
    proc = subprocess.run([sys.executable, str(path), "--module", top],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"test data generation failed ({script} --module {top}):\n"
                           f"{proc.stdout}\n{proc.stderr}")

# generate id list
ids = [f"{c['dir']}/{c['top']}" for c in config]

@pytest.mark.parametrize("cfg", config, ids=ids)
def test_runner(cfg):
    target_dir = cfg.get('dir')
    top = cfg.get('top')
    parameters = cfg.get('parameters', [])
    # nested categories (dir = "FFTs/Twiddle") map to nested Python packages
    tb_package = "testbench." + target_dir.replace("/", ".")
    generate_test_data(cfg)
    check_test_data(cfg)
    logger.info(f"config {SIM_CONFIG}, test data {TEST_DATA_ROOT}")
    
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
                    test_module=f"{tb_package}.{top}.test_{top},",
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
            # match the file name exactly: '<top>.' alone would also match
            # e.g. 'complex_multiplier.sv' when top is 'multiplier'
            fn = [p for p in find_file(f'{top}.', '../rtl')
                  if p.name.startswith(f'{top}.')]
            logger.info(f'Found file names: {fn}')
            # 2. replace the vcd file name to the new one
            replace_vcd_filename(fn[0], f'{top}_{i}.vcd')
            # 3. build the verilog modules with the parameters
            platform = parameters[i].get("PLATFORM", "")
            extra = get_vendor_sources(platform, vendor_cfgs) if platform else []
            # cocotb's Verilator runner passes parameters as -G<name>=<value>
            # verbatim, so string parameters (e.g. INIT_FILE, PLATFORM) need
            # explicit SystemVerilog quotes; a list (vector parameter, e.g.
            # munge ORDER) becomes a sized literal of 32-bit elements, the
            # first element in the MSBs
            hdl_params = {k: f'"{test_data_param(v)}"' if isinstance(v, str)
                          else vector_param(v) if isinstance(v, list) else v
                          for k, v in parameters[i].items()}
            runner.build(
                sources=sources + extra,
                hdl_toplevel=top,
                waves=True,
                defines={'SIM': ''},
                parameters=hdl_params,
                build_dir=f"sim_build/{target_dir}/{top}"
            )
            # run the tests
            runner.test(hdl_toplevel=top,
                        test_module=f"{tb_package}.{top}.test_{top},",
                        results_xml=top_result,
                        waves=True,
                        plusargs=['--trace --trace-structs']
                        )