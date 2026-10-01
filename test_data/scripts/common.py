"""Shared paths and command line for the test data generators in test_data/scripts/.

Paths: the generators run both from a repository checkout (test_data/ and
rtl/ side by side) and inside the test container, where tests/test_runner.py
calls them and the Dockerfile has copied test_data/ to /work/tests/test_data
and rtl/ to /work/rtl. Paths are therefore derived from this file's location
instead of a fixed number of parent directories. Importing this module also
makes the module-side generators (rtl/<Category>/.../scripts/) importable.

Command line (run_cli): every generator script accepts

    --module NAME   generate only this module's test data (repeatable);
                    default: every module the script covers
    --list          list the modules the script covers

and prints the [[simulations]] blocks for tests/simulation.toml of the
modules it generated.
"""

import argparse
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
# test_data/ root: data of <Category>/<module> lives in TEST_DATA_ROOT/<Category>/<module>
TEST_DATA_ROOT = SCRIPTS_DIR.parent
# rtl/ root: the first ancestor directory that contains rtl/
RTL_ROOT = next(p / "rtl" for p in SCRIPTS_DIR.parents if (p / "rtl").is_dir())
# generators that belong to RTL modules (in the modules' own scripts/ directory)
TWIDDLE_SCRIPTS = RTL_ROOT / "FFTs" / "Twiddle" / "scripts"

for _p in (SCRIPTS_DIR, TWIDDLE_SCRIPTS):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))


def run_cli(doc, generators, extra_args=None, after=None):
    """Command line shared by the generator scripts.

    generators : {module name: function() -> TOML block}; each function
                 writes that module's test data
    extra_args : optional function(parser) adding script-specific options
    after      : optional function(args, selected names) run after generating
    """
    ap = argparse.ArgumentParser(description=doc.splitlines()[0])
    ap.add_argument("--module", action="append", metavar="NAME",
                    help="generate only this module (repeatable); default: all")
    ap.add_argument("--list", action="store_true", help="list the modules this script covers")
    if extra_args:
        extra_args(ap)
    args = ap.parse_args()
    if args.list:
        print("\n".join(sorted(generators)))
        return
    names = args.module or sorted(generators)
    unknown = [n for n in names if n not in generators]
    if unknown:
        ap.error(f"unknown module(s) {unknown}; this script covers {sorted(generators)}")
    for name in sorted(names):
        print(generators[name]())
        print()
    if after:
        after(args, names)
