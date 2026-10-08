

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
// block = 'casper_library_misc.slx/bit_reverse'
// deviations = []
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// din = 'in'
// dout = 'out'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module bit_reverse #(
    parameter N_BITS = 8
)(
    input  [N_BITS-1:0] din,
    output [N_BITS-1:0] dout
);

genvar i;
generate
    for (i = 0; i < N_BITS; i = i + 1) begin : GEN_REVERSE
        assign dout[i] = din[N_BITS-1-i];
    end
endgenerate

endmodule
