# delay test data

Each subdirectory corresponds to one parameter set and has a `params.json`, which the testbench matches against the DUT parameters. `sim_din.csv` is the input and `sim_dout.csv` the expected output; `sim_rst.csv` and `sim_en.csv` drive `rst` and `en` in the sets that use them.

`simdata0` is the original 8-cycle set: the output is the input delayed by 1 clock cycle. `simdata1`–`simdata4` test `LATENCY = 0`, the reset and the enable. They are generated from a Python model of the Xilinx System Generator Delay block (`data/sysgen/block_models/xlDelay.sgm`) by `test_data/scripts/gen_basic_test_data.py`. The model clears every stage on `rst` and then shifts on `en`. Each of these sets includes a cycle with `rst` and `en` high together (stage 0 takes `din`) and one with `rst` high while `en` is low.

| Test # | Directory | LATENCY | BITWIDTH | USE_RST | USE_ENABLE | Cycles | Description |
|--------|-----------|---------|----------|---------|------------|--------|-------------|
| 0 | `simdata0` | 1 | 3 | 0 | 0 | 8 | Original set — one-cycle delay |
| 1 | `simdata1` | 0 | 4 | 0 | 0 | 200 | Wire |
| 2 | `simdata2` | 3 | 4 | 1 | 1 | 200 | Three stages with reset and enable |
| 3 | `simdata3` | 2 | 5 | 0 | 1 | 200 | Two stages with enable only |
| 4 | `simdata4` | 1 | 3 | 1 | 0 | 200 | One stage with reset only |
