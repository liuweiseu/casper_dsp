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
