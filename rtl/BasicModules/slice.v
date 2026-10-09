// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Slice'
// deviations = [
//   "Only 'Lower Bit Location + Width' relative to 'LSB of Input' is implemented; the mask default ('Upper Bit Location + Width', bit1 = 0 relative to 'MSB of Input') slices the top nbits, which is START_BIT = NBITS - WIDTH in the HDL. Ranges relative to the binary point need the offset added by hand.",
//   'There is no range check: START_BIT + WIDTH > NBITS is an out-of-range part select in the HDL (slice.v:10), while Sysgen rejects it at compile time.',
// ]
//
// [params.WIDTH]
// mask = 'nbits'
// type = 'edit'
//
// [params.START_BIT]
// mask = 'bit0'
// type = 'edit'
//
// [mask_set.mode]
// value = 'Lower Bit Location + Width'
//
// [mask_set.base0]
// value = 'LSB of Input'
//
// [hdl_only]
// NBITS = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
// mode = "HDL fixed to 'Lower Bit Location + Width' (mask default is 'Upper Bit Location + Width')"
// bit1 = 'only used by the modes the HDL does not implement'
// base1 = 'only used by the modes the HDL does not implement'
// base0 = "HDL fixed to 'LSB of Input'"
// boolean_output = 'output type only (1-bit result is the same bit)'
//
// [ports]
// note = 'The Sysgen block icon carries no port labels, so ports map by position (no rename recorded)'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module slice #(
    parameter NBITS = 8,
    parameter START_BIT = 0,
    parameter WIDTH = 1
)(
    input [NBITS-1: 0] din,
    output [WIDTH - 1 : 0] dout
);

assign dout = din[START_BIT + WIDTH - 1:START_BIT];

endmodule
