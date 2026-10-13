// twiddle_coeff_0 — twiddle stage for coefficient 0 (w = 1) with delay
// matching: every leg is only delayed
//
// Corresponds to casper_library's twiddle_coeff_0: ao = ai, bwo = bi and
// sync_out = sync_in, each through a pipeline of
//
//   LATENCY = 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY
//
// the formula casper_library uses so the latency "matches twiddle_general
// with single coefficient". It does not: a single-coefficient twiddle_general
// has MULT+ADD+CONV (a Constant coefficient), one cycle less, in casper and in
// this HDL. As in casper_library, BRAM_LATENCY is accepted but does not enter
// the formula. bwo keeps the input width (only twiddle_general
// grows bwo by one bit).
//
// INPUT_BIT_WIDTH is added for the HDL port widths. ASYNC = 1 (casper
// async): en only qualifies the data; dvalid = en delayed by the latency.
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
// block = 'casper_library_ffts_twiddle.slx/twiddle_coeff_0'
// deviations = [
//   "latency is 1+MULT_LATENCY+ADD_LATENCY+CONV_LATENCY on every leg in both models (twiddle_coeff_0_init.m latency_s); BRAM_LATENCY is accepted but unused in both. Its init comment says this 'must match twiddle_general with single coefficient', but per coeff_gen_init.m (constant coefficient, no delay) + bus_mult (mult+add, fan_latency 0) + bus_convert (conv) a single-coefficient twiddle_general has mult+add+conv, one cycle less (the HDL twiddle_general follows casper)",
//   'test vectors in casper_dsp/test_data/FFTs/Twiddle/twiddle_coeff_0/test_data.md come from a Python reference model (not exported from MATLAB), so cycle/bit equivalence with the Simulink block is unverified',
// ]
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// note = 'async = on: dvalid = en delayed 1 + mult_latency + add_latency + conv_latency by a free Delay; the data path is not gated. The HDL ports always exist, dvalid = 0 when ASYNC = 0'
// [params.ASYNC.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// INPUT_BIT_WIDTH = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
//
// [ports]
// order = 'Simulink: ai, bi, sync_in, en (async only) -> ao, bwo, sync_out, dvalid (async only) (checked on a built block for twiddle_coeff_0); HDL: the same order with ai / bi / ao / bwo split into re / im lanes'
// note = 'each Simulink complex port x is split into x_re / x_im'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module twiddle_coeff_0 #(
    parameter int N_INPUTS        = 1,
    parameter int INPUT_BIT_WIDTH = 18,
    parameter int MULT_LATENCY    = 2,
    parameter int ADD_LATENCY     = 1,
    parameter int BRAM_LATENCY    = 1,
    parameter int CONV_LATENCY    = 1,
    parameter int ASYNC           = 0
)(
    input  logic                       clk,
    input  logic [INPUT_BIT_WIDTH-1:0] ai_re  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] ai_im  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] bi_re  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] bi_im  [N_INPUTS],
    input  logic                       sync_in,
    output logic [INPUT_BIT_WIDTH-1:0] ao_re  [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] ao_im  [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] bwo_re [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] bwo_im [N_INPUTS],
    input  logic                       en = 1'b1,
    output logic                       sync_out,
    output logic                       dvalid
);

    localparam int LATENCY = 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY;

    // ASYNC = 1: en only qualifies the data; dvalid = en through a free Delay
    // of LATENCY (den, twiddle_coeff_0_init.m:28, 64-70); 0 when ASYNC = 0
    if (ASYNC != 0) begin : GEN_DVALID
        delay #(.LATENCY(LATENCY), .BITWIDTH(1)) u_dvalid (.clk(clk), .din(en), .dout(dvalid));
    end else begin : GEN_NO_DVALID
        assign dvalid = 1'b0;
    end

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_a_re (
            .clk(clk), .din(ai_re[n]), .dout(ao_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_a_im (
            .clk(clk), .din(ai_im[n]), .dout(ao_im[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_b_re (
            .clk(clk), .din(bi_re[n]), .dout(bwo_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_b_im (
            .clk(clk), .din(bi_im[n]), .dout(bwo_im[n]));
    end

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(LATENCY)) u_sync (
        .clk(clk), .din(sync_in), .dout(sync_out));

endmodule
