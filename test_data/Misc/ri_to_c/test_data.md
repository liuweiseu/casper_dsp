# ri_to_c test data

Each subdirectory corresponds to one parameter set. Input files are `sim_in_re.csv` (real part) and `sim_in_im.csv` (imaginary part); `sim_out.csv` holds the expected packed output `{re, im}`.

| Test # | Directory | RE_WIDTH | IM_WIDTH | Cycles | Description |
|--------|-----------|----------|----------|--------|-------------|
| 0 | `simdata0` | 8  | 8  | 100 | Pack two equal-width 8-bit words into a 16-bit complex word |
| 1 | `simdata1` | 16 | 8  | 100 | Pack a 16-bit real and 8-bit imaginary into a 24-bit complex word |
