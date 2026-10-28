# munge test data

Each subdirectory corresponds to one parameter set. `sim_din.csv` holds the input word and `sim_dout.csv` the expected output, one decimal value per line (up to 256 bits: the testbench parses them as Python integers). `DIV_SIZE` and `ORDER` are the mask vectors, MSB division first; `tests/simulation.toml` gives them as TOML lists, which `tests/test_runner.py` packs into 32-bit-element parameters.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT.

Simulink data: exported on 2026-10-28 in this repository's session (not by plugins-demo2). Each set is a Simulink model of `casper_library_flow_control/munge` (MATLAB R2021a, System Generator 2021.1, SNAP platform): `din` is a Concat of up to 16-bit Gateway Ins fed by Repeating Sequence Stair sources with random values (0 in the first cycle), and `dout` is read through 16-bit Slices, so wide words keep every bit. Both `sim_din.csv` and `sim_dout.csv` are the logged Simulink signals. The block is combinational: `dout` line i belongs to `din` line i.

Sets avoid mlib_devel bugs 21 and 22 (`docs/bugs.md`): no scalar `div_size` with more than one division, and set 6 names its two zero-size divisions in the order that `munge_init.m` handles correctly.

| Test # | Directory | DIVISIONS | DIV_SIZE | ORDER | Cycles | Description |
|--------|-----------|-----------|----------|-------|--------|-------------|
| 0 | `simdata0` | 16 | `[16 16 16 16 16 16 16 16 16 16 16 16 16 16 16 16]` | `[8 0 9 1 10 2 11 3 12 4 13 5 14 6 15 7]` | 64 | tut_100g Part 2 munge: 16 x 16-bit divisions, {I, Q} halves interleaved |
| 1 | `simdata1` | 4 | `[8 8 8 8]` | `[2 0 3 1]` | 64 | 4 x 8-bit divisions |
| 2 | `simdata2` | 4 | `[32 0 16 16]` | `[3 0 1 2]` | 64 | mask defaults: div_size [32 0 16 16], a zero-size division dropped |
| 3 | `simdata3` | 5 | `[3 7 1 12 5]` | `[4 4 0 2]` | 64 | unequal sizes, order repeats division 4 and leaves out 1 and 3 |
| 4 | `simdata4` | 1 | `[10]` | `[0]` | 64 | divisions = 1: din passed through, order ignored |
| 5 | `simdata5` | 3 | `[4 6 2]` | `[1 2 0]` | 64 | unequal sizes; Simulink mask `arith_type_out = Signed`, `bin_pt_out = 3` (output bits unchanged) |
| 6 | `simdata6` | 5 | `[5 0 0 9 4]` | `[3 4 0 0 2 1]` | 64 | two zero-size divisions, both named in order (the later one first) |
| 7 | `simdata7` | 4 | `[5 0 9 4]` | `[2 1 0 0 3 2]` | 64 | one zero-size division named in order; order repeats divisions and is longer than divisions |
