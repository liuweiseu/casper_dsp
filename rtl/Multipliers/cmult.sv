// Matches casper_library_multipliers/cmult (mlib_devel), behavioral-HDL
// multiplier implementation, fixed point only.
// Complex multiplier: ab = a * b (or conj(a) * b when CONJUGATED=1), with
// inputs/outputs packed as {re, im} (re in the MSBs, per ri_to_c).
//
// Structural composition of verified BasicModules:
//   delay (input registers, en chain) -> c_to_ri -> 4x multiplier (full
//   precision) -> [optional delay when PIPELINE_CMULT_EN] ->
//   2x addersubtracter (full precision) -> 2x convert -> ri_to_c.
//
// CONJUGATED=0: re = rere - imim, im = imre + reim
// CONJUGATED=1: re = rere + imim, im = imre - reim
//
// ASYNC=1 adds en/dvalid. With PIPELINED_ENABLE=1 the en is re-registered
// alongside the data (IN/MULT/ADD/CONV latencies) and emerges as dvalid;
// with PIPELINED_ENABLE=0 the same en directly gates every stage, the
// input register layer is bypassed (IN_LATENCY ignored) and dvalid is 0.
// Deviation from mlib_devel: the en chain accounts for PIPELINE_LATENCY
// when PIPELINE_CMULT_EN=1 (mlib_devel omits it and misaligns en there).
//
// Total latency = IN_LATENCY (when active) + MULT_LATENCY
//               + PIPELINE_LATENCY (when PIPELINE_CMULT_EN=1)
//               + ADD_LATENCY + CONV_LATENCY.
module cmult #(
    parameter int N_BITS_A          = 18,
    parameter int BIN_PT_A          = 17,
    parameter int N_BITS_B          = 18,
    parameter int BIN_PT_B          = 17,
    parameter int N_BITS_AB         = 37,
    parameter int BIN_PT_AB         = 14,
    parameter int QUANTIZATION      = 0,  // 0 = Truncate, 1 = Round +/-Inf, 2 = Round even
    parameter int OVERFLOW          = 0,  // 0 = Wrap, 1 = Saturate
    parameter int IN_LATENCY        = 0,
    parameter int MULT_LATENCY      = 3,
    parameter int ADD_LATENCY       = 1,
    parameter int CONV_LATENCY      = 1,
    parameter int CONJUGATED        = 0,  // 1 = compute conj(a) * b
    parameter int ASYNC             = 0,  // 1 = en/dvalid active
    parameter int PIPELINED_ENABLE  = 1,
    parameter int PIPELINE_CMULT_EN = 0,
    parameter int PIPELINE_LATENCY  = 2
)(
    input  logic                   clk,
    input  logic                   rst,
    input  logic [2*N_BITS_A-1:0]  a,      // {re_a, im_a}
    input  logic [2*N_BITS_B-1:0]  b,      // {re_b, im_b}
    input  logic                   en,
    output logic [2*N_BITS_AB-1:0] ab,     // {re_ab, im_ab}
    output logic                   dvalid  // active only when ASYNC=1 and PIPELINED_ENABLE=1
);

    localparam int BIN_PT_P   = BIN_PT_A + BIN_PT_B;
    localparam int PROD_W     = N_BITS_A + N_BITS_B;
    localparam int SUM_W      = PROD_W + 1;
    localparam int PIPE_LAT   = (PIPELINE_CMULT_EN != 0) ? PIPELINE_LATENCY : 0;
    localparam int IN_LAT_EFF = (ASYNC == 0 || PIPELINED_ENABLE != 0) ? IN_LATENCY : 0;

    // ── input register layer (a_replicate/b_replicate csp_latency) ─────────
    logic [2*N_BITS_A-1:0] a_d;
    logic [2*N_BITS_B-1:0] b_d;

    generate
        if (IN_LAT_EFF == 0) begin : gen_in_comb
            assign a_d = a;
            assign b_d = b;
        end else begin : gen_in_pipe
            delay #(.LATENCY(IN_LAT_EFF), .BITWIDTH(2*N_BITS_A))
                din_a (.clk(clk), .din(a), .dout(a_d));
            delay #(.LATENCY(IN_LAT_EFF), .BITWIDTH(2*N_BITS_B))
                din_b (.clk(clk), .din(b), .dout(b_d));
        end
    endgenerate

    // ── split into components (a_expand/b_expand) ──────────────────────────
    logic [N_BITS_A-1:0] re_a, im_a;
    logic [N_BITS_B-1:0] re_b, im_b;

    c_to_ri #(.NBITS(N_BITS_A), .BIN_PT(BIN_PT_A))
        a_split (.c(a_d), .re(re_a), .im(im_a));
    c_to_ri #(.NBITS(N_BITS_B), .BIN_PT(BIN_PT_B))
        b_split (.c(b_d), .re(re_b), .im(im_b));

    // ── en chain (en_replicate0/1/2 + den) ──────────────────────────────────
    logic en_mult, en_add, en_conv, dvalid_int;

    generate
        if (ASYNC == 0) begin : gen_sync
            assign en_mult    = 1'b1;
            assign en_add     = 1'b1;
            assign en_conv    = 1'b1;
            assign dvalid_int = 1'b0;
        end else if (PIPELINED_ENABLE == 0) begin : gen_en_direct
            assign en_mult    = en;
            assign en_add     = en;
            assign en_conv    = en;
            assign dvalid_int = 1'b0;
        end else begin : gen_en_pipe
            if (IN_LATENCY == 0) begin : gen_en0_comb
                assign en_mult = en;
            end else begin : gen_en0_pipe
                delay #(.LATENCY(IN_LATENCY), .BITWIDTH(1))
                    den0 (.clk(clk), .din(en), .dout(en_mult));
            end
            if (MULT_LATENCY + PIPE_LAT == 0) begin : gen_en1_comb
                assign en_add = en_mult;
            end else begin : gen_en1_pipe
                delay #(.LATENCY(MULT_LATENCY + PIPE_LAT), .BITWIDTH(1))
                    den1 (.clk(clk), .din(en_mult), .dout(en_add));
            end
            if (ADD_LATENCY == 0) begin : gen_en2_comb
                assign en_conv = en_add;
            end else begin : gen_en2_pipe
                delay #(.LATENCY(ADD_LATENCY), .BITWIDTH(1))
                    den2 (.clk(clk), .din(en_add), .dout(en_conv));
            end
            if (CONV_LATENCY == 0) begin : gen_en3_comb
                assign dvalid_int = en_conv;
            end else begin : gen_en3_pipe
                delay #(.LATENCY(CONV_LATENCY), .BITWIDTH(1))
                    den3 (.clk(clk), .din(en_conv), .dout(dvalid_int));
            end
        end
    endgenerate

    // ── multiplier layer (rere/imim/imre/reim), full precision ──────────────
    logic [PROD_W-1:0] rere, imim, imre, reim;

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .PRECISION(0), .ASYNC(ASYNC), .LATENCY(MULT_LATENCY)
    ) mult_rere (.clk(clk), .rst(rst), .en(en_mult), .a(re_a), .b(re_b), .p(rere));

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .PRECISION(0), .ASYNC(ASYNC), .LATENCY(MULT_LATENCY)
    ) mult_imim (.clk(clk), .rst(rst), .en(en_mult), .a(im_a), .b(im_b), .p(imim));

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .PRECISION(0), .ASYNC(ASYNC), .LATENCY(MULT_LATENCY)
    ) mult_imre (.clk(clk), .rst(rst), .en(en_mult), .a(im_a), .b(re_b), .p(imre));

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .PRECISION(0), .ASYNC(ASYNC), .LATENCY(MULT_LATENCY)
    ) mult_reim (.clk(clk), .rst(rst), .en(en_mult), .a(re_a), .b(im_b), .p(reim));

    // ── optional pipeline between multipliers and add/sub ───────────────────
    logic [PROD_W-1:0] rere_p, imim_p, imre_p, reim_p;

    generate
        if (PIPE_LAT == 0) begin : gen_pl_comb
            assign rere_p = rere;
            assign imim_p = imim;
            assign imre_p = imre;
            assign reim_p = reim;
        end else begin : gen_pl_pipe
            delay #(.LATENCY(PIPE_LAT), .BITWIDTH(PROD_W))
                dpl0 (.clk(clk), .din(rere), .dout(rere_p));
            delay #(.LATENCY(PIPE_LAT), .BITWIDTH(PROD_W))
                dpl1 (.clk(clk), .din(imim), .dout(imim_p));
            delay #(.LATENCY(PIPE_LAT), .BITWIDTH(PROD_W))
                dpl2 (.clk(clk), .din(imre), .dout(imre_p));
            delay #(.LATENCY(PIPE_LAT), .BITWIDTH(PROD_W))
                dpl3 (.clk(clk), .din(reim), .dout(reim_p));
        end
    endgenerate

    // ── add/sub layer, full precision ────────────────────────────────────────
    localparam int MODE_RE = (CONJUGATED != 0) ? 0 : 1;  // re: rere +/- imim
    localparam int MODE_IM = (CONJUGATED != 0) ? 1 : 0;  // im: imre +/- reim

    logic [SUM_W-1:0] sum_re, sum_im;

    addersubtracter #(
        .N_BITS_A(PROD_W), .BIN_PT_A(BIN_PT_P), .TYPE_A(1),
        .N_BITS_B(PROD_W), .BIN_PT_B(BIN_PT_P), .TYPE_B(1),
        .MODE(MODE_RE), .USE_CARRY_IN(0), .USE_CARRY_OUT(0),
        .ASYNC(ASYNC), .LATENCY(ADD_LATENCY)
    ) addsub_re (.clk(clk), .rst(rst), .en(en_add), .sub(1'b0), .cin(1'b0),
                 .a(rere_p), .b(imim_p), .c(sum_re), .cout());

    addersubtracter #(
        .N_BITS_A(PROD_W), .BIN_PT_A(BIN_PT_P), .TYPE_A(1),
        .N_BITS_B(PROD_W), .BIN_PT_B(BIN_PT_P), .TYPE_B(1),
        .MODE(MODE_IM), .USE_CARRY_IN(0), .USE_CARRY_OUT(0),
        .ASYNC(ASYNC), .LATENCY(ADD_LATENCY)
    ) addsub_im (.clk(clk), .rst(rst), .en(en_add), .sub(1'b0), .cin(1'b0),
                 .a(imre_p), .b(reim_p), .c(sum_im), .cout());

    // ── convert layer ────────────────────────────────────────────────────────
    logic [N_BITS_AB-1:0] ab_re, ab_im;

    convert #(
        .N_BITS_IN(SUM_W), .BIN_PT_IN(BIN_PT_P), .TYPE_IN(1),
        .N_BITS_OUT(N_BITS_AB), .BIN_PT_OUT(BIN_PT_AB), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
        .ASYNC(ASYNC), .LATENCY(CONV_LATENCY)
    ) convert_re (.clk(clk), .rst(rst), .en(en_conv), .din(sum_re), .dout(ab_re));

    convert #(
        .N_BITS_IN(SUM_W), .BIN_PT_IN(BIN_PT_P), .TYPE_IN(1),
        .N_BITS_OUT(N_BITS_AB), .BIN_PT_OUT(BIN_PT_AB), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
        .ASYNC(ASYNC), .LATENCY(CONV_LATENCY)
    ) convert_im (.clk(clk), .rst(rst), .en(en_conv), .din(sum_im), .dout(ab_im));

    // ── output packing ───────────────────────────────────────────────────────
    ri_to_c #(.NBITS(N_BITS_AB)) out_pack (.re(ab_re), .im(ab_im), .c(ab));

    assign dvalid = dvalid_int;

endmodule
