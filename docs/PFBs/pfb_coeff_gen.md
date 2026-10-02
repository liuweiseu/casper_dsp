# pfb_coeff_gen

## Description

Supplies the FIR coefficients of one input of a polyphase filter bank, with
one ROM per tap. It corresponds to casper_library's `pfb_coeff_gen`
(`pfb_coeff_gen_init.m`, `debug_mode` off), and is built as the init script
builds it:

```
sync ─► Counter (free running, up, PFB_SIZE−N_INPUTS bits, rst = sync)
         ─► fan_delay<a> (FAN_LATENCY) ─► ROM<a> (BRAM_LATENCY) ─┐   a = 1 … TOTAL_TAPS
                                    Concat (ROM1 = MSB) ─► Register (1) ─► coeff
din  ─► Delay1 (BRAM_LATENCY + 1 + FAN_LATENCY) ─► dout
sync ─► Delay  (BRAM_LATENCY + 1 + FAN_LATENCY) ─► sync_out
```

For the sample on `dout`, `coeff` holds the coefficients for counter value
`k`, which is the sample's position after the last sync (`k = 0` for the
sample right after it). `coeff[a−1]` is ROM `a` (casper's Concat input `a`;
`coeff[0]` is the MSB slice of casper's coeff bus). Each coefficient is a
`COEFF_BIT_WIDTH`-bit signed word with binary point `COEFF_BIT_WIDTH−1`.

### Coefficients (`pfb_coeff_gen_calc.m`)

```
alltaps = TOTAL_TAPS · 2^PFB_SIZE
h[i]    = window(WINDOW_TYPE, alltaps)[i] · sinc(FWIDTH · ((i + 0.5) / 2^PFB_SIZE − TOTAL_TAPS/2))
ROM a   = h[(a−1)·2^PFB_SIZE + NPUT + j·2^N_INPUTS],  j = 0 … 2^(PFB_SIZE−N_INPUTS)−1
```

Here `sinc(x) = sin(πx)/(πx)`. Note casper's half-sample time axis
`t = 0.5 : 1 : alltaps−0.5`: it makes `h` symmetric about its centre. The
test data generator checks this symmetry on the tables of all inputs and
taps.

The values are stored with round half away from zero and saturation, the
same rule as this library's twiddle tables. The module reads them from
`COEFF_DIR` + `pfb_coeff_n<NPUT>_t<a>.mem`. Generate these files with:

```bash
python3 rtl/PFBs/scripts/gen_pfb_coeffs.py --pfb-size P --total-taps T --window hamming \
        --n-inputs N --nput 0 1 --fwidth 1 --coeff-bit-width W -o DIR/
```

### Windows

The script computes MATLAB's `window(name, N)` with its default
parameters, in plain Python. Each window was checked against SciPy's
equivalent to within 1e−15.

| Supported | Notes |
|-----------|-------|
| `rectwin`, `bartlett`, `triang` | |
| `hamming`, `hann`, `blackman` | symmetric; evaluated half then mirrored, as MATLAB's `gencoswin` |
| `blackmanharris`, `nuttallwin`, `flattopwin` | MATLAB coefficient sets |
| `barthannwin`, `bohmanwin` (casper mask spelling `bohamwin`), `parzenwin` | |
| `gausswin` | α = 2.5 (MATLAB default) |
| `kaiser` | β = 0.5 (MATLAB default) |
| `tukeywin` | r = 0.5 (MATLAB default) |

Not supported, and the script stops with an error:

- `chebwin`: the Dolph–Chebyshev window with MATLAB's default 100 dB is not
  reproduced bit-exactly here.
- `userwindow`: a user-supplied function, not a table that can be generated.

### Not implemented

`WINDOW_TYPE` and `FWIDTH` only shape the tables; they are declared for
traceability. `COEFF_DIST_MEM` (distributed vs block RAM) is ignored; the
memory type follows `PLATFORM`. `DEBUG_MODE` (ROMs holding coefficient
indices) must be 0.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PFB_SIZE` | 5 | log2 of the number of PFB channels |
| `COEFF_BIT_WIDTH` | 18 | Coefficient width |
| `TOTAL_TAPS` | 4 | Number of taps (ROMs) |
| `COEFF_DIST_MEM` | 0 | Ignored |
| `WINDOW_TYPE` | `"hamming"` | Window of the tables |
| `BRAM_LATENCY` | 2 | ROM latency (≥ 1) |
| `N_INPUTS` | 1 | log2 of the parallel inputs (`PFB_SIZE − N_INPUTS ≥ 1`) |
| `NPUT` | 0 | Which input this generator serves (0 … 2^N_INPUTS−1) |
| `FWIDTH` | 1.0 | Filter width factor of the sinc |
| `FAN_LATENCY` | 1 | Address fan-out delay per ROM |
| `DIN_WIDTH` | 8 | Width of the `din` / `dout` pass-through |
| `COEFF_DIR` | `""` | Directory prefix of the ROM files |
| `PLATFORM` | `"GENERIC"` | Memory primitives |
| `DEBUG_MODE` | 0 | Must be 0 |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Sync; restarts the address counter |
| `din` | input | `DIN_WIDTH` | Data, passed through with the coefficient latency |
| `sync_out` | output | 1 | `sync` delayed `BRAM_LATENCY + 1 + FAN_LATENCY` cycles |
| `dout` | output | `DIN_WIDTH` | `din` delayed `BRAM_LATENCY + 1 + FAN_LATENCY` cycles |
| `coeff` | output | `COEFF_BIT_WIDTH` × `TOTAL_TAPS` | Coefficients of the taps for the sample on `dout` |
