# sync_gen

## Description

Generates a periodic sync pulse or a software-triggered one, as the
casper_library block `casper_library_misc/sync_gen`.

### Software registers

The block contains three software registers (swreg, From Processor,
32 bits). The HDL does not implement these yellow blocks. Each register
value is an input port instead:

| Port | Yellow block | Bits used | Software register name |
|------|--------------|-----------|------------------------|
| `sync` | `<sync_gen>/sync` | 0 | `<design>_<path>_sync` (e.g. `sync_gen_sync`) |
| `sync_period_sel` | `<sync_gen>/sync_period_sel` | 0 | `..._sync_period_sel` |
| `sync_period_var` | `<sync_gen>/sync_period_var` | 31:0 | `..._sync_period_var` |

The wrapper that connects these ports must keep the register names.

In Simulink simulation, the swreg sim ports are tied to constants inside the
block: `sync = 1`, `sync_period_sel = 0` and `sync_period_var = 0`.

### Structure

The constant is set by `sync_gen_init.m`:

```
period_const = SCALE·SIM_ACC_LEN·PFB_FIR_TAPS·FFT_SIZE·lcm(REORDER_VEC)/FFT_SIMULT_INPUTS − 2   (Signed 32-bit)
period       = sync_period_sel[0] ? sync_period_var : period_const               (Mux, Fix_33_0)
restart      = reg(period == counter) | rising_edge(sync[0])                      (Relational latency 1)
counter      = 32-bit free running, synchronous reset by restart
sync_out     = rising_edge(restart)
```

How the output behaves:

- **Period:** with `sync_period_sel = 0`, `sync_out` pulses every
  `period_const + 2` cycles. With `sync_period_sel = 1`, it pulses every
  `sync_period_var + 2` cycles.
- **Software sync:** a rising edge on `sync[0]` restarts the period and gives
  a pulse.
- **Pulse width:** `sync_out` is one cycle wide.

The module is built from `constant`, `slice`, `edge_detect`, `multiplexer`,
`relational`, `logical` and `counter`.

### Parameter checks

The module stops with `$fatal` when:

- the period is not an integer;
- `period − 2` does not fit the Signed 32-bit constant;
- `PFB_FIR_TAPS < 1`;
- a `REORDER_VEC` element is not positive.

### REORDER_VEC

`REORDER_VEC` is packed: 32-bit elements, with the first element in the
MSBs, as in munge `ORDER`. `{32'd2, 32'd2, 32'd9}` is the mask vector
`[2 2 9]`.

The tut_spec configuration (`1, 4096, 8, 4, [2 2 9], 4096`) gives a period
of 150994944 and a constant of 150994942.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SIM_ACC_LEN` | 2 | mask `sim_acc_len` |
| `FFT_SIZE` | 1024 | mask `fft_size` |
| `FFT_SIMULT_INPUTS` | 4 | mask `fft_simult_inputs` |
| `PFB_FIR_TAPS` | 4 | mask `pfb_fir_taps` |
| `REORDER_VEC` | `{32'd2, 32'd2}` | mask `reorder_vec` (packed vector) |
| `SCALE` | 1 | mask `scale` |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 32 | swreg `sync` value (bit 0: software sync, rising edge) |
| `sync_period_sel` | input | 32 | swreg `sync_period_sel` value (bit 0: 1 = use `sync_period_var`) |
| `sync_period_var` | input | 32 | swreg `sync_period_var` value (period − 2) |
| `sync_out` | output | 1 | Sync pulse (Simulink `sync_out`) |
