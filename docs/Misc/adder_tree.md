# adder_tree

## Description

A pipelined sum of `N_INPUTS` values. It corresponds to casper_library's
`adder_tree` (fixed point, `dvalid_en` off), and is built as
`adder_tree_init.m` builds it: the inputs are reduced pairwise, stage by
stage, and the odd value of a stage is carried on through a delay.

```
cur_n = N_INPUTS
while cur_n > 1:
    n_adds = floor(cur_n / 2), n_dlys = cur_n mod 2
    node j < n_adds  = node 2j + node 2j+1 of the previous stage   (AddSub)
    node n_adds      = node cur_n−1, delayed LATENCY                (only if cur_n is odd)
    cur_n = n_adds + n_dlys
```

For example, 5 inputs reduce as 5 → 3 → 2 → 1. The fifth input is carried
through stage 1, then the sum of inputs 3 and 4 is carried through stage 2.

There are `STAGES = ceil(log2(N_INPUTS))` stages of `LATENCY` cycles each
(casper's `csp_latency`). `dout` and `sync_out` come `STAGES·LATENCY` cycles
after `din` and `sync`; `sync` goes through a plain delay line, as in casper.
With `N_INPUTS = 1`, `din[0]` is wired straight to `dout`.

The adders are [`adder_subtractor`](../Bus/adder_subtractor.md) instances
and the delays are [`pipeline`](../Delays/pipeline.md) instances.

### Adder precision

| `PRECISION` | Adders | `dout` width |
|-------------|--------|--------------|
| 0 (Full) | casper's AddSub default, which `adder_tree_init.m` leaves unchanged. Every add grows one integer bit; binary point `BIN_PT`, type `TYPE` | `DATA_WIDTH + STAGES` |
| 1 (User defined) | Every adder outputs `N_BITS_OUT` bits, binary point `BIN_PT_OUT`, signed, using `QUANTIZATION` / `OVERFLOW`. This is how `pfb_fir_real_init.m` sets the tree's `addr*` blocks (with Truncate and Wrap). Carried odd values keep their format until their next add | `N_BITS_OUT` (`DATA_WIDTH` if `N_INPUTS = 1`) |

The output width is `N_BITS_OUT_EFF`. With `PRECISION = 1` and
`N_BITS_OUT = DATA_WIDTH`, `BIN_PT_OUT = BIN_PT`, the output is as wide as
the inputs.

### Not implemented

`FIRST_STAGE_HDL` (casper `first_stage_hdl` / pfb `adder_folding`) and
`ADDER_IMP` (`Fabric` / `DSP48` / `Behavioral`) choose how the adders are
implemented, not what they compute. They are declared for traceability and
ignored. `DVALID_EN` and `FLOATING_POINT` must be 0.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 3 | Number of values summed |
| `DATA_WIDTH` | 18 | Input width |
| `BIN_PT` | 0 | Input binary point |
| `TYPE` | 1 | Input type: `0` = unsigned, `1` = signed |
| `LATENCY` | 1 | Latency per stage (casper `csp_latency`); `0` = combinational |
| `PRECISION` | 0 | `0` = full precision, `1` = user-defined adder format |
| `N_BITS_OUT`, `BIN_PT_OUT` | 18, 0 | Adder output format (`PRECISION = 1`) |
| `QUANTIZATION` | 0 | `0` = truncate, `1` = round ±inf, `2` = round even (`PRECISION = 1`) |
| `OVERFLOW` | 0 | `0` = wrap, `1` = saturate (`PRECISION = 1`) |
| `FIRST_STAGE_HDL`, `ADDER_IMP` | 0 | Ignored |
| `DVALID_EN`, `FLOATING_POINT` | 0 | Must be 0 |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Sync |
| `din` | input | `DATA_WIDTH` × `N_INPUTS` | Values to sum |
| `sync_out` | output | 1 | `sync` delayed `STAGES·LATENCY` cycles |
| `dout` | output | `N_BITS_OUT_EFF` | Sum, `STAGES·LATENCY` cycles later |
