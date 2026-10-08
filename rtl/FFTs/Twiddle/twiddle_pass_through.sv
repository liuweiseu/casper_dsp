// twiddle_pass_through — twiddle stage for coefficient 0 in the first biplex
// stage: every leg is a plain wire, zero latency
//
// Corresponds to casper_library's twiddle_pass_through: ao = ai, bwo = bi,
// sync_out = sync_in (w = 1, no delay matching). Same port shape as the other
// twiddle_* modules; bwo has the input width, as in casper_library (only
// twiddle_general grows bwo by one bit).
//
// INPUT_BIT_WIDTH is added for the HDL port widths (the Simulink block is
// width-agnostic). ASYNC is declared for traceability; must be 0.
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
// hdl_unsupported = [1]
// note = 'async=on (dvi/dvo pass-through ports) is not implemented: elaboration stops with $fatal'
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
// note = 'each Simulink complex port x is split into x_re / x_im'
// [ports.renamed]
// [ports.missing]
// dvi = 'async=on only (not implemented)'
// dvo = 'async=on only (not implemented)'
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
    output logic                       sync_out
);

    if (ASYNC != 0) $fatal(1, "twiddle_pass_through: ASYNC is not implemented");

    assign ao_re    = ai_re;
    assign ao_im    = ai_im;
    assign bwo_re   = bi_re;
    assign bwo_im   = bi_im;
    assign sync_out = sync_in;

endmodule
