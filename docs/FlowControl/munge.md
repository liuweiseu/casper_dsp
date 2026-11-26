# munge

## Description

Splits `din` into `DIVISIONS` divisions and concatenates them in the order
`ORDER`, matching the casper_library block
`casper_library_flow_control/munge`. The module is combinational and has no
clock.

Both vectors count the divisions from the MSB, as Simulink does:

- `munge_init.m` splits `din` with `bus_expand`. Output port k of
  `bus_expand` is the k-th division from the MSB.
- It then joins them with `bus_create`, whose input 1 is the MSB.

So division k of `din` sits below the first k divisions, and

```
dout = { din division ORDER[0], din division ORDER[1], ... }   (MSB first)
```

Example: the tut_100g Part 2 munge has `DIVISIONS = 16`, 16-bit divisions
and `ORDER = [8 0 9 1 10 2 … 15 7]`. Its input is `{I, Q}` from a
`bus_create`, with I (divisions 0–7) above Q (divisions 8–15). The output
interleaves them from the MSB: Q0, I0, Q1, I1, …, Q7, I7, where Ik and Qk
are the k-th 16-bit words from the MSB. The `dout` width is
256 bits.

Rules:

- **Zero-size divisions:** a division of size 0 has no bits. The `ORDER`
  entries naming it are dropped.
- **ORDER length:** `ORDER` may repeat divisions, leave some out, and have
  any length. The `dout` width is the sum of the sizes it names.
- **One division:** with `DIVISIONS = 1`, `dout = din` and `ORDER` is
  ignored.

### Vector parameters

`DIV_SIZE` and `ORDER` are packed 32-bit elements with the first element in
the MSBs, so they read like the mask vector:

```systemverilog
munge #(
    .DIVISIONS(4),
    .DIV_SIZE({32'd32, 32'd0, 32'd16, 32'd16}),   // div_size = [32 0 16 16]
    .ORDER({32'd3, 32'd0, 32'd1, 32'd2})           // order    = [3 0 1 2]
) u_munge (.din(din), .dout(dout));
```

The parameters have no declared type, so each one's length is `$bits / 32`
of the value given. `DIV_SIZE` has either one element (every division that
size) or `DIVISIONS` elements.

In `tests/simulation.toml` they are TOML lists (`ORDER = [3, 0, 1, 2]`).
`tests/test_runner.py` turns each list into a sized literal
(`128'h00000003000000000000000100000002`) for Verilator's `-G` option.

### Differences from Simulink

The full list is in the HDL-Simulink mapping in `rtl/FlowControl/munge.sv`.

- **`din` width:**
  - The HDL fixes it at the sum of the division sizes.
  - Simulink takes it from the signal and ignores any extra LSBs.
  - With `divisions = 1`, Simulink passes a `din` of any width through.
- **Output type:** `arith_type_out` and `bin_pt_out` only reinterpret
  `dout` in Simulink. The HDL outputs the same raw bits.
- **mlib_devel bugs 21 and 22** (`docs/bugs.md`): Simulink cannot build, or
  builds wrongly, two kinds of configuration. The HDL implements the
  intended behaviour for both:
  - **Bug 21:** a scalar `div_size` with more than one division.
  - **Bug 22:** an `order` that names several zero-size divisions.

### Parameter checks

The module stops with `$fatal` when:

- `DIVISIONS < 1`;
- `DIV_SIZE` has neither 1 nor `DIVISIONS` elements, or has a negative
  element;
- the division sizes are all 0;
- an `ORDER` element is outside `0 … DIVISIONS−1`;
- `ORDER` names only divisions of size 0.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DIVISIONS` | 4 | Number of divisions of `din` (mask `divisions`) |
| `DIV_SIZE` | `{32'd32, 32'd0, 32'd16, 32'd16}` | Division sizes in bits, MSB division first; one element = all divisions that size (mask `div_size`) |
| `ORDER` | `{32'd3, 32'd0, 32'd1, 32'd2}` | `din` division placed in each `dout` division, MSB first (mask `order`) |

The defaults are the mask defaults. The mask's `arith_type_out` and
`bin_pt_out` have no HDL parameter.

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `din` | input | sum of `DIV_SIZE` (`DIVISIONS · DIV_SIZE` for one element) | Input word |
| `dout` | output | sum of the sizes `ORDER` names (`din` width when `DIVISIONS = 1`) | Reordered word |
