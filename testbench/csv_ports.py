"""Load test data CSVs by DUT port name.

A scalar port has one file, sim_<port>.csv. An array port has one file per
element, sim_<port>0.csv, sim_<port>1.csv, ... (file j = element j). Every
file holds one value per line, row i = cycle i.
"""

from pathlib import Path

import numpy as np


def element_files(datadir, port):
    """sim_<port>0.csv, sim_<port>1.csv, ... in element order (may be empty)."""
    files = []
    while (f := Path(datadir) / f"sim_{port}{len(files)}.csv").exists():
        files.append(f)
    return files


def load_rows(datadir, port):
    """Port data as a list of rows, row i = [element 0, element 1, ...] at cycle i.

    A scalar port (sim_<port>.csv) gives one-element rows.
    """
    single = Path(datadir) / f"sim_{port}.csv"
    if single.exists():
        return np.loadtxt(single, dtype=int, ndmin=2).tolist()
    files = element_files(datadir, port)
    if not files:
        raise FileNotFoundError(f"no sim_{port}.csv or sim_{port}0.csv in {datadir}")
    return np.column_stack([np.loadtxt(f, dtype=int, ndmin=1) for f in files]).tolist()


def load_packed(datadir, port, width):
    """Packed array port [N-1:0][width-1:0] as Python ints, element k in bits
    [k*width +: width] (values may exceed 64 bits)."""
    cols = [[int(x) for x in f.read_text().split()] for f in element_files(datadir, port)]
    if not cols:
        raise FileNotFoundError(f"no sim_{port}0.csv in {datadir}")
    return [sum(v << (k * width) for k, v in enumerate(row)) for row in zip(*cols)]
