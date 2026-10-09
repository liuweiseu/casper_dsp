// negate — two's-complement negation with output requantization
//
// dout = convert(-din)
//
// The negation is formed at full precision (N_BITS_IN + 1 bits, signed), so
// -(most negative input) and negated unsigned inputs are exact; the result is
// then requantized to the output format by a convert instance, which also
// provides the CSP_LATENCY pipeline. Corresponds to a single lane of
// casper_library's bus_negate (Xilinx Negate block).
//
// Encodings (common to all fixed-point modules in rtl/Bus/ and
// rtl/Multipliers/):
//   TYPE_*       : 0 = unsigned, 1 = signed
//   QUANTIZATION : 0 = truncate, 1 = round half away from zero,
//                  2 = round half to even
//   OVERFLOW     : 0 = wrap, 1 = saturate (2 = flag as error -> wrap)
//   CSP_LATENCY      : 0 = combinational, N > 0 = N register stages
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
// block = 'casper_library_bus.slx/bus_negate'
// deviations = [
//   'The HDL matches bus_negate only with TYPE_IN=1, N_BITS_OUT=N_BITS_IN, BIN_PT_OUT=BIN_PT_IN and TYPE_OUT=1. Simulink always negates a signed input into the same signed format (bus_negate_init.m:155,201-203). Any other HDL setting has no Simulink counterpart.',
//   "Negating the most negative input overflows the output format: with OVERFLOW=0 (Wrap) both give the most negative value again, and with OVERFLOW=1 both saturate to the maximum. With OVERFLOW=2 ('Flag as error', bus_negate_init.m:181) Simulink stops with an overflow error, while the HDL wraps.",
//   'The mask default overflow is 1 (Saturate), but the HDL default OVERFLOW is 0 (Wrap). Set OVERFLOW explicitly to reproduce a default bus_negate.',
// ]
//
// [mask_set.floating_point]
// value = 'off'
//
// [hdl_only]
// TYPE_IN = 'bus_negate always reinterprets the input as signed (bus_expand outputArithmeticType=ones, bus_negate_init.m:155)'
// N_BITS_OUT = "bus_negate's output width is always n_bits_in (bus_negate_init.m:201,212)"
// BIN_PT_OUT = "bus_negate's output binary point is always bin_pt_in (bus_negate_init.m:201,212)"
// TYPE_OUT = "bus_negate's output is always Signed (bus_negate_init.m:202,213)"
// QUANTIZATION = "bus_negate hard-codes 'Truncate' (bus_negate_init.m:203,214); with the input format kept no LSBs are dropped"
//
// [mask_missing]
// cmplx = 'single real lane: complex lanes are not modelled'
// misc = 'misc pass-through (misci/misco ports) is not implemented'
// float_type = 'floating point is not implemented'
// exp_width = 'floating point is not implemented'
// frac_width = 'floating point is not implemented'
// n_vectors = 'single lane: the lane count is not modelled'
//
// [ports]
// [ports.renamed]
// [ports.missing]
// misci = 'misc=on only (not implemented)'
// misco = 'misc=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module negate #(
    parameter int N_BITS_IN    = 8,
    parameter int BIN_PT_IN    = 4,
    parameter int TYPE_IN      = 1,
    parameter int N_BITS_OUT   = 8,
    parameter int BIN_PT_OUT   = 4,
    parameter int TYPE_OUT     = 1,
    parameter int QUANTIZATION = 0,
    parameter int OVERFLOW     = 0,
    parameter int CSP_LATENCY  = 1
)(
    input  logic                  clk,
    input  logic [N_BITS_IN-1:0]  din,
    output logic [N_BITS_OUT-1:0] dout
);

    localparam int N_BITS_FULL = N_BITS_IN + 1;

    logic signed [N_BITS_FULL-1:0] din_s;
    logic signed [N_BITS_FULL-1:0] neg;

    assign din_s = {(TYPE_IN != 0) ? din[N_BITS_IN-1] : 1'b0, din};
    assign neg   = -din_s;

    convert #(
        .N_BITS_IN (N_BITS_FULL), .BIN_PT_IN (BIN_PT_IN),  .TYPE_IN (1),
        .N_BITS_OUT(N_BITS_OUT),  .BIN_PT_OUT(BIN_PT_OUT), .TYPE_OUT(TYPE_OUT),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CSP_LATENCY)
    ) u_convert (
        .clk (clk),
        .din (neg),
        .dout(dout)
    );

endmodule
