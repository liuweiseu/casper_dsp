// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Constant'
// deviations = [
//   "Simulink quantizes the real 'const' to {arith_type, n_bits, bin_pt} with Round and Saturate (xlConstant.sgm: xtype(OUTPUT_TYPE, op_val) with xlRound, xlSaturate); the HDL outputs the integer VAL[NBITS-1:0] unscaled and wraps out-of-range values, so pass VAL = round(const*2^bin_pt) already saturated to the output range (constant.sv:8).",
//   "VAL is a 32-bit 'int', so NBITS > 32 is not supported: VAL[NBITS-1:0] selects past bit 31 and a negative VAL is not sign-extended (constant.sv:3,8).",
//   'Boolean, Floating-point and DSP48-instruction constants are not implemented.',
// ]
//
// [params.NBITS]
// mask = 'n_bits'
// type = 'edit'
//
// [params.VAL]
// mask = 'const'
// type = 'edit'
// expr = 'VAL < 0 ? VAL + (1 << NBITS) : VAL'
// note = "raw bit pattern; a negative VAL is its two's-complement low NBITS bits (constant.sv:58)"
//
// [mask_set.arith_type]
// value = 'Unsigned'
//
// [mask_set.bin_pt]
// value = 0
//
// [hdl_only]
//
// [mask_missing]
// gui_display_data_type = 'HDL is always a raw fixed-point bit vector (no Boolean / Floating-point)'
// arith_type = 'signedness only changes how VAL is quantized; HDL VAL is already the bit pattern'
// bin_pt = 'HDL VAL is the raw integer pattern (real value * 2^bin_pt)'
// preci_type = 'floating point not implemented'
// exp_width = 'floating point not implemented'
// frac_width = 'floating point not implemented'
// explicit_period = 'sample period has no HDL meaning'
// period = 'sample period has no HDL meaning'
// equ = 'DSP48 instruction mode not implemented'
// opselect = 'DSP48 instruction mode not implemented'
// inp2 = 'DSP48 instruction mode not implemented'
// opr = 'DSP48 instruction mode not implemented'
// inp1 = 'DSP48 instruction mode not implemented'
// carry = 'DSP48 instruction mode not implemented'
//
// [ports]
// note = 'Simulink output port 1 is unlabelled (the icon shows the value); maps to out'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module constant #(
    parameter int NBITS = 8,
    parameter int VAL   = 0
)(
    output logic [NBITS-1:0] out
);

    assign out = VAL[NBITS-1:0];

endmodule
