# fft_stage_n

## Description

One stage of a biplex (streaming radix-2 DIF) FFT. It corresponds to
casper_library's `fft_stage_n` (fixed-point, synchronous). Two streams `in1`
and `in2` enter together. A commutator pairs each sample of one half-frame
with the sample `ND = 2^(FFT_SIZE − FFT_STAGE)` cycles later, and a
[`butterfly_direct`](butterfly_direct.md) combines each pair:

```
in1  ─► delay P ─────────► x1 ─┐          ┌─► mux1 ─► delay P+ND ─► a ┐
in2  ─► delay P+ND ──────► x2 ─┼─ sel ────┤                           ├─ butterfly_direct ─► out1, out2
                               │          └─► mux0 ─► delay P ─────► b ┘
sync ─► delay P ─► counter (FFT_SIZE−FFT_STAGE+1 bits, reset) ─► sel = MSB
     └─► delay P+MUX_LATENCY ─► sync_delay(ND) ─► butterfly sync_in

mux1 = sel ? x2 : x1        mux0 = sel ? x1 : x2        (latency MUX_LATENCY)
```

This is the dataflow of `fft_stage_n_init.m`. Its chain of
`din0`/`din1`/`din2`/`delay0`/`delay1`/`dmux0`/`dmux1`/`dsync0..2` delays is
merged here into single delay lines with the same end-to-end timing.

### Derived Timing (as `fft_stage_n_init.m`)

| Quantity | Value |
|----------|-------|
| RAM delays | `DELAYS_BRAM = 1` and `ND ≥ BRAM_LATENCY`. The long delays (`P+ND`) then use [`delay_bram`](../Delays/delay_bram.md); otherwise registers. |
| `FAN_LATENCY` | With RAM delays: `max(min, ⌈log2(n_brams) / max(1, log2 MAX_FANOUT)⌉ − 1)`, where `n_brams = ⌈2·N_INPUTS·INPUT_BIT_WIDTH / word⌉` and `word` comes from casper's BRAM word-size table for `FFT_SIZE − FFT_STAGE`. Without RAM delays, `n_inputs` replaces `n_brams`. `min` is 1 when `MAX_FANOUT ≤ 1`, otherwise 0. |
| `P` | `FAN_LATENCY`, plus `BRAM_LATENCY` with RAM delays |
| `MUX_LATENCY` | 1 if `2·N_INPUTS·INPUT_BIT_WIDTH ≤ 200`, otherwise 2 |
| Data and sync latency | `2·P + MUX_LATENCY + ND` + the butterfly latency |

The logarithm ratio is computed with exact integer arithmetic, as the
smallest `k` with `MAX_FANOUT^k ≥ n`.

### Butterfly Configuration

The butterfly gets casper's stage coefficients:
- `Coeffs = [0]` for stage 1, otherwise `0 … 2^(FFT_STAGE−1) − 1`.
- `StepPeriod = FFT_SIZE − FFT_STAGE`, biplex on.

As a result, stage 1 uses `twiddle_pass_through`, stage 2 uses
`twiddle_stage_2`, and later stages use `twiddle_general`. For
`twiddle_general`, `INIT_FILE` must hold the table:

```
python3 scripts/gen_twiddle_coeffs.py --fft-size FFT_SIZE \
    --coeffs 0 1 … 2^(FFT_STAGE-1)-1 --coeff-bit-width COEFF_BIT_WIDTH -o table.mem
```

The butterfly's dynamic downshift is `shift[FFT_STAGE−1]`. The stage's
`of = butterfly of | of_in`, registered for one cycle.

## Parameters

| Parameter         | Default     | Description |
|-------------------|-------------|-------------|
| `N_INPUTS`        | 1           | Complex lanes per stream |
| `FFT_SIZE`        | 5           | casper `FFTSize` (log2 of the FFT length) |
| `FFT_STAGE`       | 5           | casper `FFTStage` (1 … `FFT_SIZE`) |
| `INPUT_BIT_WIDTH` | 18          | Lane width (signed) |
| `BIN_PT_IN`       | 17          | Lane binary point |
| `COEFF_BIT_WIDTH` | 18          | Twiddle coefficient width |
| `BITGROWTH`       | 0           | Butterfly bit growth (outputs `INPUT_BIT_WIDTH + 1` bits) |
| `DOWNSHIFT`       | 0           | Static downshift (with `HARDCODE_SHIFTS`) |
| `HARDCODE_SHIFTS` | 0           | Static shift instead of `shift[FFT_STAGE−1]` |
| `ADD_LATENCY`, `MULT_LATENCY`, `BRAM_LATENCY`, `CONV_LATENCY` | 1, 2, 1, 1 | As casper |
| `QUANTIZATION`    | 1           | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`        | 0           | `0`=wrap, `1`=saturate |
| `DELAYS_BRAM`     | 1           | Put the long delays in RAM (see above) |
| `MAX_FANOUT`      | 1           | Sets `FAN_LATENCY` (here and in the butterfly) |
| `INIT_FILE`       | `""`        | `twiddle_general` table (stages ≥ 3) |
| `PLATFORM`        | `"GENERIC"` | Passed to the RAMs / ROM |

**Declared but not implemented:** `ASYNC` and `FLOATING_POINT` must be 0. These
are ignored: `FLOAT_TYPE`, `EXP_WIDTH`, `FRAC_WIDTH`, `ADD_PIPE_LATENCY`,
`MULT_PIPE_LATENCY`, `COEFFS_BIT_LIMIT`, `COEFF_SHARING`, `COEFF_DECIMATION`,
`USE_HDL`, `USE_EMBEDDED`, `DSP48_ADDERS`, `REG_RETIMING`. `N_BITS_OUT` is
derived.

## Ports

Lane ports are unpacked arrays of `N_INPUTS` words.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `in1_re`, `in1_im`, `in2_re`, `in2_im` | input | `INPUT_BIT_WIDTH` × `N_INPUTS` | The two input streams |
| `of_in` | input | `N_INPUTS` | Overflow flags from the previous stage |
| `sync` | input | 1 | Frame sync |
| `shift` | input | `FFT_SIZE` | Shift bus; bit `FFT_STAGE−1` is used |
| `out1_re`, `out1_im`, `out2_re`, `out2_im` | output | `N_BITS_OUT` × `N_INPUTS` | Butterfly outputs `a + bw` / `a − bw` |
| `of` | output | `N_INPUTS` | `butterfly of | of_in`, registered |
| `sync_out` | output | 1 | Sync aligned with the outputs |
