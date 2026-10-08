

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
// block = 'casper_library_misc.slx/ri_to_c'
// deviations = [
//   'Simulink concatenates re (MSB) and im at their own widths after reinterpreting each as unsigned with binary point 0 (system_157.xml), so re and im may differ in width. The HDL requires both to be NBITS wide.',
// ]
//
// [hdl_only]
// NBITS = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module ri_to_c #(
    parameter NBITS = 8
)(
    input  [NBITS-1:0] re,
    input  [NBITS-1:0] im,
    output [2*NBITS-1:0] c
);

assign c = {re, im};

endmodule
