"""Where a testbench finds its test data.

The test data root is $CASPER_TEST_DATA when it is set (a directory laid
out exactly like test_data/), otherwise the test_data/ directory next to
testbench/ (the repository's test_data/ in a checkout, its copy
tests/test_data/ in the test container). A module's data directory is the
root plus the testbench's path below testbench/, e.g.
testbench/FFTs/Twiddle/twiddle_general/ -> <root>/FFTs/Twiddle/twiddle_general/.
"""

import os
from pathlib import Path

TEST_DATA_ENV = "CASPER_TEST_DATA"
_TB_ROOT = Path(__file__).resolve().parent


def test_data_root():
    """The test data root directory."""
    env = os.environ.get(TEST_DATA_ENV)
    return Path(env).resolve() if env else _TB_ROOT.parent / "test_data"


def module_data_dir(testbench_file):
    """Data directory of the module whose testbench is `testbench_file`."""
    here = Path(testbench_file).resolve().parent
    return test_data_root() / here.relative_to(_TB_ROOT)


# keep pytest from collecting the helper above as a test
test_data_root.__test__ = False
