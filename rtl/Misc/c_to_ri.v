

//
// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'casper_library_misc.slx/c_to_ri'
// deviations = [
//   'BIN_PT has no effect in the HDL (raw bit slices). In Simulink, bin_pt only sets the Signed type of re/im through the force_re/force_im Reinterpret blocks (system_4.xml). The bits are identical.',
//   "Simulink takes re as the top n_bits and im as the bottom n_bits of c (Slice 'Upper/Lower Bit Location + Width', system_4.xml), so a c wider than 2*n_bits loses its middle bits. The HDL requires c to be exactly 2*N_BITS wide.",
// ]
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module c_to_ri #(
    parameter N_BITS = 8,
    parameter BIN_PT = 7
)(
    input  [2*N_BITS-1:0] c,
    output [N_BITS-1:0] re,
    output [N_BITS-1:0] im
);

assign re = c[2*N_BITS-1:N_BITS];
assign im = c[N_BITS-1:0];

endmodule
