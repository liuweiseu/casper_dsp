// twiddle_coeff_0 — twiddle stage for coefficient 0 (w = 1) with delay
// matching: every leg is only delayed
//
// Corresponds to casper_library's twiddle_coeff_0: ao = ai, bwo = bi and
// sync_out = sync_in, each through a pipeline of
//
//   LATENCY = 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY
//
// the formula casper_library uses so the latency "matches twiddle_general
// with single coefficient", letting butterfly_direct swap twiddle variants
// transparently (equal to twiddle_general's latency when its
// BRAM_LATENCY = 1). As in casper_library, BRAM_LATENCY is accepted but does
// not enter the formula. bwo keeps the input width (only twiddle_general
// grows bwo by one bit).
//
// INPUT_BIT_WIDTH is added for the HDL port widths. ASYNC is declared for
// traceability; must be 0.

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
    output logic                       sync_out
);

    localparam int LATENCY = 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY;

    if (ASYNC != 0) $fatal(1, "twiddle_coeff_0: ASYNC is not implemented");

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_re (
            .clk(clk), .din(ai_re[n]), .dout(ao_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_im (
            .clk(clk), .din(ai_im[n]), .dout(ao_im[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_b_re (
            .clk(clk), .din(bi_re[n]), .dout(bwo_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_b_im (
            .clk(clk), .din(bi_im[n]), .dout(bwo_im[n]));
    end

    pipeline #(.BITWIDTH(1), .LATENCY(LATENCY)) u_sync (
        .clk(clk), .din(sync_in), .dout(sync_out));

endmodule
