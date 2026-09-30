// twiddle_stage_2 — twiddle stage for Coeffs = [0 1] with
// StepPeriod = FFT_SIZE-2: w alternates between 1 and -j
//
// Corresponds to casper_library's twiddle_stage_2 (fixed-point, synchronous).
// Behavior derived from twiddle_stage_2_init.m:
//
//   sync_in ─► Delay(bram_latency) ─► Counter (FFTSize-1 bits, rst) ─► Slice (MSB) = sel
//   bi real lane ─► Delay(bram) ─► mux0 d0 ┐  mux0 (latency mult+conv+add) ─► bwo real
//   bi imag lane ─► Delay(bram) ─► mux0 d1 ┘
//   bi imag lane ─► Delay(bram) ─► Delay(...) ─► mux1 d0 ┐  mux1 ─► bwo imag
//   bi real lane ─► bus_negate(sat) ─► Delay(...) ─► mux1 d1 ┘
//
// so, with sel = MSB of a counter cleared by the delayed sync:
//
//   sel = 0 : bwo = ( bi_re,  bi_im)   (w = 1)
//   sel = 1 : bwo = ( bi_im, -bi_re)   (w = -j, negation saturates)
//
// The counter restarts at 0 for the first sample after a sync pulse, so the
// first 2^(FFT_SIZE-2) samples of each frame use w = 1 and the next
// 2^(FFT_SIZE-2) use w = -j. The delays inside casper_library's version are
// arranged so every path to the output mux lines up; here the same result is
// built as: delay bi / sync by BRAM_LATENCY, select with sel, then pipeline
// the selection by MULT_LATENCY + CONV_LATENCY + ADD_LATENCY (inside
// BasicModules/multiplexer).
//
// Every leg (ai→ao, bi→bwo, sync) has latency
//   LATENCY = BRAM_LATENCY + MULT_LATENCY + CONV_LATENCY + ADD_LATENCY
// (BRAM_LATENCY is used here, unlike twiddle_coeff_0/1 which use a fixed 1).
// bwo keeps the input width and binary point. FFT_SIZE >= 2.
//
// Declared for traceability only: ASYNC and FLOATING_POINT must be 0;
// FLOAT_TYPE, EXP_WIDTH and FRAC_WIDTH are ignored.

module twiddle_stage_2 #(
    parameter int N_INPUTS        = 1,
    parameter int FFT_SIZE        = 5,
    parameter int INPUT_BIT_WIDTH = 18,
    parameter int BIN_PT_IN       = 17,
    parameter int ADD_LATENCY     = 1,
    parameter int MULT_LATENCY    = 2,
    parameter int BRAM_LATENCY    = 2,
    parameter int CONV_LATENCY    = 2,
    parameter int ASYNC           = 0,
    parameter int FLOATING_POINT  = 0,
    parameter int FLOAT_TYPE      = 1,
    parameter int EXP_WIDTH       = 8,
    parameter int FRAC_WIDTH      = 24
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

    localparam int MUX_LATENCY = MULT_LATENCY + CONV_LATENCY + ADD_LATENCY;
    localparam int LATENCY     = BRAM_LATENCY + MUX_LATENCY;
    localparam int CNT_BITS    = FFT_SIZE - 1;

    if (ASYNC != 0)          $fatal(1, "twiddle_stage_2: ASYNC is not implemented");
    if (FLOATING_POINT != 0) $fatal(1, "twiddle_stage_2: FLOATING_POINT is not implemented");
    if (FFT_SIZE < 2)        $fatal(1, "twiddle_stage_2: FFT_SIZE must be >= 2");

    // ── coefficient select: MSB of a counter cleared by the delayed sync ─────
    logic                sync_d;
    logic [CNT_BITS-1:0] cnt;
    logic                sel;

    pipeline #(.BITWIDTH(1), .LATENCY(BRAM_LATENCY)) u_sync_d (
        .clk(clk), .din(sync_in), .dout(sync_d));

    counter #(
        .COUNTER_TYPE   (0),              // free running, cleared by rst
        .NBITS          (CNT_BITS),
        .COUNT_DIR      (0),
        .INIT_VAL       (0),
        .STEP           (1),
        .ENABLE_SYNC_RST(1),
        .ENABLE_ENABLE  (0)
    ) u_counter (
        .clk   (clk),
        .rst   (sync_d),
        .enable(1'b1),
        .dout  (cnt)
    );

    assign sel = cnt[CNT_BITS-1];

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        logic [INPUT_BIT_WIDTH-1:0] b_re_d, b_im_d, b_re_neg;

        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(BRAM_LATENCY)) u_b_re_d (
            .clk(clk), .din(bi_re[n]), .dout(b_re_d));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(BRAM_LATENCY)) u_b_im_d (
            .clk(clk), .din(bi_im[n]), .dout(b_im_d));

        negate #(
            .N_BITS_IN (INPUT_BIT_WIDTH), .BIN_PT_IN (BIN_PT_IN), .TYPE_IN (1),
            .N_BITS_OUT(INPUT_BIT_WIDTH), .BIN_PT_OUT(BIN_PT_IN), .TYPE_OUT(1),
            .QUANTIZATION(0), .OVERFLOW(1), .LATENCY(0)
        ) u_neg_re (.clk(clk), .din(b_re_d), .dout(b_re_neg));

        // mux0: real part of bwo = sel ? im : re
        multiplexer #(.NBITS(INPUT_BIT_WIDTH), .NINPUTS(2), .LATENCY(MUX_LATENCY)) u_mux_re (
            .clk (clk),
            .din ('{b_re_d, b_im_d}),
            .sel (sel),
            .dout(bwo_re[n])
        );

        // mux1: imaginary part of bwo = sel ? -re : im
        multiplexer #(.NBITS(INPUT_BIT_WIDTH), .NINPUTS(2), .LATENCY(MUX_LATENCY)) u_mux_im (
            .clk (clk),
            .din ('{b_im_d, b_re_neg}),
            .sel (sel),
            .dout(bwo_im[n])
        );

        // a leg: delay-matched only
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_re (
            .clk(clk), .din(ai_re[n]), .dout(ao_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_im (
            .clk(clk), .din(ai_im[n]), .dout(ao_im[n]));
    end

    pipeline #(.BITWIDTH(1), .LATENCY(MUX_LATENCY)) u_sync_out (
        .clk(clk), .din(sync_d), .dout(sync_out));

endmodule
