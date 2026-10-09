# fft_wideband_real architecture

## Overview

[`fft_wideband_real`](fft_wideband_real.md) computes an `N = 2^FFT_SIZE`-point
real FFT while taking `P = 2^N_INPUTS` samples per stream per clock cycle. It
does not build all `FFT_SIZE` stages in parallel hardware. Instead it splits
the transform with the Cooley-Tukey decimation-in-time decomposition into
three parts, one per core submodule:

| Submodule | FFT stages | How it computes | Role |
|-----------|------------|-----------------|------|
| [`fft_biplex_real_4x`](fft_biplex_real_4x.md) | first `FFT_SIZE − N_INPUTS` | serial in time, RAM delay lines | an `M`-point FFT of each input lane |
| [`fft_direct`](fft_direct.md) | last `N_INPUTS` | parallel in space, hard-wired butterflies | twiddle and combine the `P` lane spectra into the `N`-point spectrum |
| [`fft_unscrambler`](fft_unscrambler.md) (optional) | none | transpose and reorder | put the bins into natural order |

This page explains what each part computes and why the split works. The
module page [`fft_wideband_real`](fft_wideband_real.md) has the wiring,
parameters, widths, overflow handling and memory files.

## Notation

| Symbol | Meaning |
|--------|---------|
| `F` | `FFT_SIZE`; the FFT length is `N = 2^F` |
| `NI` | `N_INPUTS`; `P = 2^NI` real samples per stream per cycle |
| `M` | `2^(F−NI) = N/P`; cycles per frame, and the length of each lane's sub-FFT |
| `W_L` | `exp(−2πj/L)` |

`N_STREAMS` independent streams are processed side by side; everything below
describes one stream.

## Input layout: each lane is a decimated sub-sequence

Sample `t·P + n` of a frame arrives on input `in<s><n>` in frame cycle `t`.
Lane `n` therefore carries

```
x_n[t] = x[t·P + n],   t = 0 … M−1
```

i.e. every `P`-th sample of the frame, starting at `n`. The `P` lanes are the
`P` decimated sub-sequences of the decimation-in-time FFT.

## The decomposition

Splitting the DFT sum by `n = i mod P` and writing the output bin as
`k = k0 + m·M` (`0 ≤ k0 < M`, `0 ≤ m < P`) gives

```
X[k0 + m·M] = Σ_{n=0}^{P−1}  W_P^(n·m) · ( W_N^(n·k0) · X_n[k0] )

X_n[k0]     = Σ_{t=0}^{M−1}  x_n[t] · W_M^(t·k0)        (M-point FFT of lane n)
```

The three factors map onto the three blocks:

1. `X_n[k0]`: an `M`-point FFT of every lane, computed by `fft_biplex_real_4x`.
2. `W_N^(n·k0)` and `Σ_n … W_P^(n·m)`: a twiddle multiply followed by a
   `P`-point FFT across the lanes, computed by `fft_direct`.
3. The bin index `k0 + m·M` is not the natural output order, so
   `fft_unscrambler` reorders the bins.

## 1. fft_biplex_real_4x: the first F − N_INPUTS stages

**What it computes:** the `M`-point FFT `X_n[k0]` of every lane. These are the
first `F − NI` stages of the `N`-point FFT.

**How:**
- [`biplex_core`](biplex_core.md) is a pipelined FFT that processes one sample
  per cycle per lane, with
  [`fft_stage_n`](fft_stage_n.md) stages (a
  [`butterfly_direct`](butterfly_direct.md) plus RAM delay lines) in
  series. One core handles two complex signals at once ("biplex").
- The inputs are real, so four real lanes are packed into two complex signals
  (`pol_in[4j] + j·pol_in[4j+1]` and `pol_in[4j+2] + j·pol_in[4j+3]`) and
  share one core. This is the "4x" in the name.
- [`bi_real_unscr_4x`](Internal/bi_real_unscr_4x.md) uses the conjugate
  symmetry of real spectra ([`hilbert`](Internal/hilbert.md),
  [`mirror_spectrum`](Internal/mirror_spectrum.md)) to separate the four real
  spectra again. Its [`reorder`](../Reorder/reorder.md) blocks also undo the
  bit-reversed order of the biplex output.

**Output:** in frame cycle `k0`, lane `n` carries `X_n[k0]`, the bin `k0` of
its own sub-sequence's spectrum, in natural order.

The wideband top instantiates one `fft_biplex_real_4x` with its
`N_INPUTS = N_STREAMS·2^(NI−2)` biplex lanes (4 real lanes each) and
`FFT_SIZE = F − NI`. This is why `2^NI·N_STREAMS` must be a multiple of 4.

### Inside the serial part

The following walks through the serial part with the example
`FFT_SIZE = 10`, `N_INPUTS = 3` (`N = 1024`, `P = 8`, `M = 128`), so
`fft_biplex_real_4x` runs with `FFT_SIZE = 7`.

#### How the lanes share hardware

Mathematically the `P` lanes are independent `M`-point FFTs: no lane's data
enters another lane's result. The hardware is not `P` separate pipelines,
though. Lanes share it at three levels:

| Level | What is shared | Effect on the values |
|-------|----------------|----------------------|
| Real pairs as complex | Two real lanes form one complex signal `z = x_a + j·x_b` | The two spectra come out mixed and must be separated (step 3) |
| Biplex | Two complex signals `pol1`, `pol2` take turns on one butterfly per stage | None; they only alternate in time |
| Biplex lanes | All lanes of one `biplex_core` share the counters, `sync` and the twiddle ROM (one coefficient per cycle for every lane); each lane has its own butterfly, multiplier and delay-line slice | None; only control is shared |

The smallest unit of the implementation is therefore one biplex lane, which
carries four real lanes. In the example the eight real lanes form two biplex
lanes of one `biplex_core` (`N_INPUTS = 2`):

```
biplex lane 0:  pol1 = x0 + j·x1    pol2 = x2 + j·x3
biplex lane 1:  pol1 = x4 + j·x5    pol2 = x6 + j·x7
```

The two biplex lanes are identical, so the steps below follow lane 0
(`x0 … x3`).

```
x0, x1 ─► z1 = x0 + j·x1 ─┐
x2, x3 ─► z2 = x2 + j·x3 ─┴─► biplex_core: 7 × fft_stage_n ─► bi_real_unscr_4x ─► X0[k] … X3[k]
                               (Z1[k], Z2[k])                  (separate, reorder)
```

#### Step 1: real pairs as complex signals

The FFT is linear, so `FFT(x0 + j·x1) = X0[k] + j·X1[k]`. One complex FFT
gives the mixed spectra of two real signals, which halves the arithmetic.

#### Step 2: the biplex_core pipeline

Each frame is `M = 128` cycles; `z1` and `z2` each deliver one sample per
cycle. The seven [`fft_stage_n`](fft_stage_n.md) stages are in series, and
stage `s` pairs samples `ND = 2^(7−s)` apart:

| Stage | ND | Coefficients | Twiddle | Multiplier |
|-------|----|--------------|---------|------------|
| 1 | 64 | 1 (`w = 1`) | [`twiddle_pass_through`](Twiddle/twiddle_pass_through.md) | none |
| 2 | 32 | 2 (`1`, `−j`) | [`twiddle_stage_2`](Twiddle/twiddle_stage_2.md) | none (swap and negate) |
| 3 | 16 | 4 | [`twiddle_general`](Twiddle/twiddle_general.md) | yes |
| 4 | 8 | 8 | `twiddle_general` | yes |
| 5 | 4 | 16 | `twiddle_general` | yes |
| 6 | 2 | 32 | `twiddle_general` | yes |
| 7 | 1 | 64 | `twiddle_general` | yes |

Inside each stage (stage 1, `ND = 64`, as the example):

1. **Delay lines:** `in2` is delayed by `ND` cycles, so the two streams are
   half a period apart.
2. **Commutator:** a select signal (the counter MSB) toggles every `ND`
   cycles. For `ND` cycles the butterfly gets a pair of `z1` samples `ND`
   apart (`z1[t]`, `z1[t+64]`), for the next `ND` cycles a pair of `z2`
   samples `ND` apart, and so on.
3. **Butterfly:** every cycle it outputs `a + b·w` on `out1` and `a − b·w` on
   `out2`.
4. **Next stage:** `out1` carries the sums of both streams and `out2` the
   differences. In the radix-2 decomposition each is an independent
   half-size sub-problem, and they become the two inputs of the next stage,
   which pairs samples `ND/2` apart.

The distance halves from stage to stage; at stage 7 neighbouring samples are
paired and the 128-point FFT is complete. The butterfly works every cycle,
half the time on `z1` and half on `z2`. This is the point of the biplex
structure: a single-stream pipeline would leave the butterfly idle while it
waits for the first half of each frame.

The pairing was checked with a symbolic trace of the stage model
(`m_fft_stage` in `test_data/scripts/gen_fft_stage_test_data.py`), which
uses the same delays and mux as the RTL.

Other details per stage:
- **Twiddles:** stage `s` steps to the next coefficient every `ND` cycles
  (`STEP_PERIOD = 7 − s`). The coefficients come from a counter-addressed ROM
  holding `twiddle_stage<s>.mem`. The ROM is shared by all biplex lanes; each
  lane has its own complex multiplier.
- **Scaling:** each butterfly can halve its result (`shift`, against bit
  growth), and [`convert_of`](../Misc/convert_of.md) rounds and saturates.
- **Storage:** stage `s` delays about `2·ND` words per lane, so the whole core
  stores about `2M` words per lane. Long delays use
  [`delay_bram`](../Delays/delay_bram.md) and short ones registers
  (`DELAYS_BIT_LIMIT`, `BRAM_LATENCY`).
- **Cost:** `F − NI` butterflies per lane, against `(M/2)·(F − NI)` for a
  fully parallel `M`-point FFT.

#### Step 3: bi_real_unscr_4x

The `biplex_core` output has two problems.

**The order is scrambled.** The first half-frame (64 cycles) carries `Z1`,
the second `Z2`. In frame cycle `k`, `out1` holds bin `bit_rev(k)` and `out2`
bin `bit_rev(k) + 64`. `reorder` blocks with the maps `map_even.mem` /
`map_odd.mem` restore natural order, and half-frame delays align `Z1` with
`Z2`.

**Two real spectra are mixed.** A real signal's spectrum satisfies
`X[N−k] = conj(X[k])`, so the two signals can be recovered from `Z[k]` and
`Z[N−k]` (up to scaling):

```
X0[k] = ( Z1[k] + conj(Z1[128−k]) ) / 2
X1[k] = ( Z1[k] − conj(Z1[128−k]) ) / (2j)
```

[`hilbert`](Internal/hilbert.md) does these additions and subtractions;
[`mirror_spectrum`](Internal/mirror_spectrum.md) and `reorder_out` provide
the mirrored bin `Z[N−k]` at the same time as `Z[k]` and fill in the other
half of the spectrum.

The four spectra `X0 … X3` then leave together, one bin per lane per cycle,
`k = 0 … 127` in natural order, and go to `fft_direct`.

## 2. fft_direct: the last N_INPUTS stages

**What it computes:** for each cycle `k0`, the twiddle `W_N^(n·k0)` on lane
`n` followed by a `P`-point FFT across the `P` lanes. The result is the `P`
bins `X[k0 + m·M]`, `m = 0 … P−1`. These are the last `NI` stages of the
`N`-point FFT.

**How:**
- `NI` stages of `butterfly_direct` are wired in parallel, so all `P` lanes
  are processed every cycle.
- `MAP_TAIL = 1` with `LARGER_FFT_SIZE = F` and `START_STAGE = F − NI + 1`
  makes `fft_direct` the tail of the larger `N`-point FFT. The twiddles of the
  larger FFT change with `k0`, so each butterfly steps through a coefficient
  table, one entry per cycle of the biplex frame
  ([`twiddle_general`](Twiddle/twiddle_general.md) and its ROM), restarted by
  `sync`.

**Output:** in frame cycle `k0`, output lane `m` carries bin `X[k0 + m·M]`.
The input is real, so `X[N−k] = conj(X[k])` and the upper half is redundant:
only lanes `m < P/2` (bins `0 … N/2−1`) are kept, the others are left
unconnected in the top.

## 3. fft_unscrambler: natural bin order

**Why it is needed:** after `fft_direct`, cycle `t` lane `n` carries bin
`t + n·M`; neighbouring lanes are `M` bins apart. Natural order means cycle
`t` lane `n` carries bin `t·(P/2) + n`, i.e. neighbouring lanes hold
neighbouring bins. The two orders are a transpose of the (cycle × lane) grid.

**How:**
- [`square_transposer`](../Reorder/square_transposer.md) transposes
  square blocks across the lanes.
- [`reorder`](../Reorder/reorder.md) permutes the frame in time (a corner
  turn) over the `M`-cycle frame. Its map rotates the `(F − NI)`-bit cycle
  index left by `NI − 1` bits (the unscrambler runs with
  `FFT_SIZE = F − 1` and `N_INPUTS = NI − 1`).

**When it is present:** only with `UNSCRAMBLE = 1` and `N_INPUTS > 1`
(`N_INPUTS = 1` turns it off, as casper does). A downstream block that
reorders bins anyway can do without it and save its RAM and latency. With the
unscrambler, `sync` must recur every `ORDER·M` cycles (`ORDER` of the reorder
map) instead of every `M` cycles.

## Example: FFT_SIZE = 5, N_INPUTS = 2

`N = 32`, `P = 4` samples per cycle, `M = 8` cycles per frame, two output
lanes (bins 0 … 15):

| Cycle `t` | Without unscrambler: lane 0, lane 1 | With unscrambler: lane 0, lane 1 |
|-----------|-------------------------------------|----------------------------------|
| 0 | 0, 8 | 0, 1 |
| 1 | 1, 9 | 2, 3 |
| 2 | 2, 10 | 4, 5 |
| … | … | … |
| 7 | 7, 15 | 14, 15 |

Both orders were read from the bit-exact model in
`test_data/scripts/gen_fft_wideband_test_data.py`, which checks every output
frame against numpy's FFT. The same holds for `FFT_SIZE = 6` with
`N_INPUTS = 2` and `3`.

## Why split the FFT this way

- **Resources:** most stages (`F − NI`) run in the biplex part, one sample per
  cycle per lane with RAM delay lines. Their cost grows slowly with the FFT
  length.
- **Throughput:** only `NI` stages need to handle `P` samples per cycle, and
  only those are built fully in parallel by `fft_direct`.
- **Result:** the block accepts `P` samples per cycle without building the
  whole `N`-point FFT in parallel hardware.
