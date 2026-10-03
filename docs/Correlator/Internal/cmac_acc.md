# cmac_acc

## Description

The accumulate-and-relay cell inside casper_library's `cmac` (`casper_library_correlator.slx`, `system_871` "acc" and `system_886` "acc1"). It is not a library block; `cmac` uses one copy for the real part and one for the imaginary part.

```
q        <= rst ? din : q + din        Xilinx Accumulator, hasbypass on, Wrap, latency 1, power-on 0
acc_out   = rst ? q : acc_in           Mux, latency 2
valid_out = rst ? 1 : valid_in         Mux, latency 2
```

`hasbypass` is the Xilinx Accumulator option "Reinitialize with input 'b' on reset". When `rst` is high the accumulator loads the current `din` instead of clearing, so consecutive integrations have no gap between them. On the `rst` cycle `q` still holds the finished sum, and the muxes put it on `acc_out` two cycles later. On every other cycle `acc_in`/`valid_in` are relayed with the same 2-cycle delay. The diagram's Convert1 (din to `N_BITS`) and its latency-0 Delays are wires.

Built from `register` and `multiplexer` ×2.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_BITS` | 16 | Accumulator / data width (cmac's `n_bits_out`); the sum wraps in `N_BITS` bits |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `rst` | input | 1 | End of integration: dump `q`, reload with `din` |
| `din` | input | `N_BITS` | Value to accumulate |
| `acc_in` | input | `N_BITS` | Relay input |
| `valid_in` | input | 1 | Relay valid |
| `acc_out` | output | `N_BITS` | `q` two cycles after `rst`, otherwise `acc_in` delayed 2 |
| `valid_out` | output | 1 | 1 two cycles after `rst`, otherwise `valid_in` delayed 2 |
