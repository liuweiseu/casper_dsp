// twiddle_coeff_1 — twiddle stage for coefficient 1 (w = -j)
//
// Corresponds to casper_library's twiddle_coeff_1. Its datapath, taken
// literally from twiddle_coeff_1_init.m:
//
//   bi ─► munge (split all real parts | all imaginary parts)
//        real lane ─► bus_negate (saturate) ──────┐
//        imag lane ─► Delay ─────────────────────┐│
//                         bus_create(imag, -real) ─► munge (re-interleave) ─► bwo
//
// bus_create places the delayed imaginary lane where the real part was and
// the negated real lane where the imaginary part was, so per lane
//
//   bwo_re = bi_im            bwo_im = -bi_re     (= -j · bi)
//
// which is the product with Coeffs = [1]: w = exp(-2πj·2^(FFTSize-2)/2^FFTSize)
// = -j. The negation saturates (bus_negate overflow = 1), so -(-2^(N-1))
// becomes 2^(N-1)-1; bwo keeps the input width and binary point.
//
// Every leg (ai→ao, both bi lanes, sync) has the same latency
//   LATENCY = 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY
// (casper_library: "must match twiddle_general with single coefficient");
// BRAM_LATENCY is accepted but, as in casper_library, not used.
// ASYNC is declared for traceability; must be 0.

module twiddle_coeff_1 #(
    parameter int N_INPUTS        = 1,
    parameter int INPUT_BIT_WIDTH = 18,
    parameter int BIN_PT_IN       = 17,
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

    if (ASYNC != 0) $fatal(1, "twiddle_coeff_1: ASYNC is not implemented");

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        // a leg: delay-matched only
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_re (
            .clk(clk), .din(ai_re[n]), .dout(ao_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_im (
            .clk(clk), .din(ai_im[n]), .dout(ao_im[n]));

        // imaginary lane, delayed, becomes the real part of bwo
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_b_im (
            .clk(clk), .din(bi_im[n]), .dout(bwo_re[n]));

        // negated (saturating) real lane becomes the imaginary part of bwo
        negate #(
            .N_BITS_IN (INPUT_BIT_WIDTH), .BIN_PT_IN (BIN_PT_IN), .TYPE_IN (1),
            .N_BITS_OUT(INPUT_BIT_WIDTH), .BIN_PT_OUT(BIN_PT_IN), .TYPE_OUT(1),
            .QUANTIZATION(0), .OVERFLOW(1), .LATENCY(LATENCY)
        ) u_neg_re (.clk(clk), .din(bi_re[n]), .dout(bwo_im[n]));
    end

    pipeline #(.BITWIDTH(1), .LATENCY(LATENCY)) u_sync (
        .clk(clk), .din(sync_in), .dout(sync_out));

endmodule
