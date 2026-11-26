// twiddle_pass_through — twiddle stage for coefficient 0 in the first biplex
// stage: every leg is a plain wire, zero latency
//
// Corresponds to casper_library's twiddle_pass_through: ao = ai, bwo = bi,
// sync_out = sync_in (w = 1, no delay matching). Same port shape as the other
// twiddle_* modules; bwo has the input width, as in casper_library (only
// twiddle_general grows bwo by one bit).
//
// INPUT_BIT_WIDTH is added for the HDL port widths (the Simulink block is
// width-agnostic). ASYNC = 1 (casper async): dvo = dvi.
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
// block = 'casper_library_ffts_twiddle.slx/twiddle_pass_through'
// deviations = []
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// note = 'async = on: dvo = dvi (a wire); the HDL ports always exist, dvo = 0 when ASYNC = 0'
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
// order = 'Simulink: ai, bi, sync_in, dvi (async only) -> ao, bwo, sync_out, dvo (async only) (checked on a built block); HDL: the same order with ai / bi / ao / bwo split into re / im lanes'
// note = 'each Simulink complex port x is split into x_re / x_im'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module twiddle_pass_through #(
    parameter int N_INPUTS        = 1,
    parameter int INPUT_BIT_WIDTH = 18,
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
    input  logic                       dvi = 1'b1,
    output logic                       sync_out,
    output logic                       dvo
);

    // ASYNC = 1: dvo = dvi (twiddle_pass_through_init.m:23-66); 0 when ASYNC = 0
    assign dvo = (ASYNC != 0) ? dvi : 1'b0;

    assign ao_re    = ai_re;
    assign ao_im    = ai_im;
    assign bwo_re   = bi_re;
    assign bwo_im   = bi_im;
    assign sync_out = sync_in;

endmodule
