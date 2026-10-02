// mirror_spectrum — complete the upper half of four real-signal spectra
//
// Corresponds to casper_library's mirror_spectrum (fixed point, sync mode,
// mirror_spectrum_init.m). Each of the four channels i has a direct input
// din<i> (bins 0 … 2^(FFT_SIZE-1) of a real signal's spectrum, in order) and
// reo_in<i> (the same bins in reverse order, from a reorder). Per frame of
// 2^FFT_SIZE samples, counted from the cycle after sync:
//
//   count ≤ 2^(FFT_SIZE-1) : dout<i> = din<i>             (delayed)
//   count > 2^(FFT_SIZE-1) : dout<i> = conj(reo_in<i>)    (X[N-k] = X*[k])
//
// as casper's Relational a>b of the count against 2^(FFT_SIZE-1) drives the
// mux (d0 = din, d1 = conj). With REP = ceil(log2(N_INPUTS)) (casper's
// bus_replicate of the select):
//
//   din<i>    ─► delay 1+BRAM_LATENCY+NEGATE_LATENCY ─► mux d0 ┐
//   reo_in<i> ─► complex_conj (latency CC, Wrap)     ─► mux d1 ├─ mux (1) ─► dout<i>
//   sync ─► delay 1+BRAM_LATENCY+NEGATE_LATENCY-REP ─► counter rst ─► a>b ─► delay REP ─► sel
//                                                   └─► delay 1+REP ─► sync_out
//
// CC = 3 for NEGATE_MODE = 1 (casper "dsp48e"), NEGATE_LATENCY otherwise.
// sync_out comes 2+BRAM_LATENCY+NEGATE_LATENCY cycles after sync, and the
// first output sample (count 0) the cycle after sync_out. BRAM_LATENCY is
// the latency of the reorder in front of reo_in<i> (bi_real_unscr_4x passes
// bram_latency + map_latency + 2 + fanout_latency).
//
// ASYNC (en / dvalid) is declared for traceability; must be 0.

module mirror_spectrum #(
    parameter int N_INPUTS        = 1,
    parameter int FFT_SIZE        = 8,
    parameter int INPUT_BIT_WIDTH = 18,
    parameter int BIN_PT_IN       = 17,
    parameter int BRAM_LATENCY    = 2,
    parameter int NEGATE_LATENCY  = 1,
    parameter int NEGATE_MODE     = 0,
    parameter int ASYNC           = 0
)(
    input  logic                       clk,
    input  logic                       sync,
    input  logic [INPUT_BIT_WIDTH-1:0] din0_re    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] din0_im    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in0_re [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in0_im [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] din1_re    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] din1_im    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in1_re [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in1_im [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] din2_re    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] din2_im    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in2_re [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in2_im [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] din3_re    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] din3_im    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in3_re [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] reo_in3_im [N_INPUTS],
    output logic                       sync_out,
    output logic [INPUT_BIT_WIDTH-1:0] dout0_re   [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] dout0_im   [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] dout1_re   [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] dout1_im   [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] dout2_re   [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] dout2_im   [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] dout3_re   [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] dout3_im   [N_INPUTS]
);

    localparam int BW   = INPUT_BIT_WIDTH;
    localparam int REP  = $clog2(N_INPUTS);
    localparam int DLY  = 1 + BRAM_LATENCY + NEGATE_LATENCY;
    localparam int CC   = (NEGATE_MODE == 1) ? 3 : NEGATE_LATENCY;
    localparam int HALF = 1 << (FFT_SIZE - 1);

    if (ASYNC != 0)    $fatal(1, "mirror_spectrum: ASYNC is not implemented");
    if (FFT_SIZE < 1)  $fatal(1, "mirror_spectrum: FFT_SIZE must be >= 1");
    if (DLY < REP)     $fatal(1, "mirror_spectrum: 1 + BRAM_LATENCY + NEGATE_LATENCY < ceil(log2(N_INPUTS))");

    // ── channels as arrays ───────────────────────────────────────────────────
    logic [BW-1:0] din_re [4][N_INPUTS], din_im [4][N_INPUTS];
    logic [BW-1:0] reo_re [4][N_INPUTS], reo_im [4][N_INPUTS];
    logic [BW-1:0] out_re [4][N_INPUTS], out_im [4][N_INPUTS];

    assign din_re = '{din0_re, din1_re, din2_re, din3_re};
    assign din_im = '{din0_im, din1_im, din2_im, din3_im};
    assign reo_re = '{reo_in0_re, reo_in1_re, reo_in2_re, reo_in3_re};
    assign reo_im = '{reo_in0_im, reo_in1_im, reo_in2_im, reo_in3_im};
    assign dout0_re = out_re[0];  assign dout0_im = out_im[0];
    assign dout1_re = out_re[1];  assign dout1_im = out_im[1];
    assign dout2_re = out_re[2];  assign dout2_im = out_im[2];
    assign dout3_re = out_re[3];  assign dout3_im = out_im[3];

    // ── select ───────────────────────────────────────────────────────────────
    logic                sync0, upper, sel;
    logic [FFT_SIZE-1:0] cnt;

    pipeline #(.BITWIDTH(1), .LATENCY(DLY - REP)) u_sync_delay0 (.clk(clk), .din(sync), .dout(sync0));
    pipeline #(.BITWIDTH(1), .LATENCY(1 + REP)) u_sync_delay1 (.clk(clk), .din(sync0), .dout(sync_out));

    counter #(
        .COUNTER_TYPE(0), .NBITS(FFT_SIZE), .COUNT_DIR(0), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0)
    ) u_counter (.clk(clk), .rst(sync0), .enable(1'b1), .dout(cnt));

    // casper Relational a>b (a = count, b = 2^(FFT_SIZE-1)), latency 0
    relational #(.NBITS(FFT_SIZE), .COMP(3), .LATENCY(0)) u_relational (
        .clk(clk), .a(cnt), .b(FFT_SIZE'(HALF)), .out(upper));

    // sel_replicate: bus_replicate with latency REP
    pipeline #(.BITWIDTH(1), .LATENCY(REP)) u_sel_replicate (.clk(clk), .din(upper), .dout(sel));

    // ── data ─────────────────────────────────────────────────────────────────
    for (genvar i = 0; i < 4; i++) begin : GEN_CH
        logic [BW-1:0] conj_re [N_INPUTS], conj_im [N_INPUTS];

        complex_conj #(
            .N_INPUTS(N_INPUTS), .N_BITS(BW), .BIN_PT(BIN_PT_IN), .LATENCY(CC), .OVERFLOW(0)
        ) u_complex_conj (
            .clk(clk), .din_re(reo_re[i]), .din_im(reo_im[i]),
            .dout_re(conj_re), .dout_im(conj_im));

        for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
            logic [BW-1:0] d_re, d_im;

            pipeline #(.BITWIDTH(BW), .LATENCY(DLY)) u_delay_re (.clk(clk), .din(din_re[i][n]), .dout(d_re));
            pipeline #(.BITWIDTH(BW), .LATENCY(DLY)) u_delay_im (.clk(clk), .din(din_im[i][n]), .dout(d_im));

            // bus_mux (cmplx): d0 = delayed din, d1 = conj(reo_in), latency 1
            multiplexer #(.NBITS(BW), .NINPUTS(2), .LATENCY(1)) u_dmux_re (
                .clk(clk), .din('{d_re, conj_re[n]}), .sel(sel), .dout(out_re[i][n]));
            multiplexer #(.NBITS(BW), .NINPUTS(2), .LATENCY(1)) u_dmux_im (
                .clk(clk), .din('{d_im, conj_im[n]}), .sel(sel), .dout(out_im[i][n]));
        end
    end

endmodule
