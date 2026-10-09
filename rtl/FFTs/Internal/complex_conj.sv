// complex_conj — complex conjugate of N_INPUTS lanes
//
// Corresponds to casper_library's complex_conj (fixed point,
// complex_conj_init.m): the real part is delayed CSP_LATENCY cycles
// (real_delay), the imaginary part is negated by a bus_negate of the same
// width and binary point with latency CSP_LATENCY (Truncate, OVERFLOW 0 = Wrap,
// 1 = Saturate). With Wrap the most negative imaginary value stays as it is.
// Built from Delays/pipeline and Bus/negate.
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
// block = 'casper_library_misc.slx/complex_conj'
// deviations = [
//   'the library block is in casper_library_misc.slx (SID 415); casper_dsp files it under FFTs/Internal',
//   "the library block's saved mask default is floating_point='on' (casper_library_misc.slx system_root.xml, SID 415: n_bits/bin_pt greyed out, complex_conj_init.m:69 then uses n_bits=exp_width+frac_width, bin_pt=0); the HDL is fixed point only, so a freshly dropped block must be switched to floating_point='off' before its results can be compared",
//   "with overflow='Flag as error' the Xilinx Negate inside bus_negate (bus_negate_init.m:182, 210-214) stops the simulation when the most negative imaginary value is negated; the HDL wraps it to itself (OVERFLOW 2 behaves as 0)",
//   'Simulink carries all lanes as one packed bus z / z* (munge + bus_expand, complex_conj_init.m); the HDL uses unpacked din_re/din_im arrays, lane n = Simulink complex lane n',
//   'test vectors in casper_dsp/test_data/FFTs/Internal/complex_conj/test_data.md come from a Python reference model (not exported from MATLAB), so cycle/bit equivalence with the Simulink block is unverified',
// ]
//
// [params.OVERFLOW]
// mask = 'overflow'
// type = 'popup'
// note = "HDL OVERFLOW = 2 wraps (rtl/Bus/convert.sv:137 saturates only for 1), so it is exported as 'Wrap'; the mask's 'Error'/'Flag as error' option does not build or would flag instead of wrapping"
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Wrap'
//
// [hdl_only]
//
// [mask_missing]
// floating_point = 'floating point is not implemented'
// float_type = 'floating point is not implemented'
// exp_width = 'floating point is not implemented'
// frac_width = 'floating point is not implemented'
//
// [ports]
// note = "each Simulink complex port x is split into x_re / x_im; 'z*' is not a legal HDL identifier"
// [ports.renamed]
// din_re = 'z'
// din_im = 'z'
// dout_re = 'z*'
// dout_im = 'z*'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module complex_conj #(
    parameter int N_INPUTS    = 1,
    parameter int N_BITS      = 18,
    parameter int BIN_PT      = 17,
    parameter int CSP_LATENCY = 1,
    parameter int OVERFLOW    = 0
)(
    input  logic              clk,
    input  logic [N_BITS-1:0] din_re  [N_INPUTS],
    input  logic [N_BITS-1:0] din_im  [N_INPUTS],
    output logic [N_BITS-1:0] dout_re [N_INPUTS],
    output logic [N_BITS-1:0] dout_im [N_INPUTS]
);

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        pipeline #(.BITWIDTH(N_BITS), .CSP_LATENCY(CSP_LATENCY)) u_real_delay (
            .clk(clk), .din(din_re[n]), .dout(dout_re[n]));

        negate #(
            .N_BITS_IN(N_BITS), .BIN_PT_IN(BIN_PT), .TYPE_IN(1),
            .N_BITS_OUT(N_BITS), .BIN_PT_OUT(BIN_PT), .TYPE_OUT(1),
            .QUANTIZATION(0), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CSP_LATENCY)
        ) u_imag_negate (.clk(clk), .din(din_im[n]), .dout(dout_im[n]));
    end

endmodule
