// cmult — casper_library complex multiplier (casper_library_multipliers/cmult)
//
// ab = convert(a * b)          (CONJUGATED = 0)
// ab = convert(a * conj(b))    (CONJUGATED = 1)
//
// Structure (cmult_init.m, fixed-point path):
//
//   a ─► pipeline(IN_LATENCY) ─► {a_re, a_im}
//   b ─► pipeline(IN_LATENCY) ─► {b_re, b_im}
//   rere = a_re*b_re  imim = a_im*b_im  imre = a_im*b_re  reim = a_re*b_im
//        (Mult, Full precision, MULT_LATENCY)
//   [pipeline(PIPELINE_LATENCY) on the four products, embedded multipliers
//    with PIPELINE_CMULT_EN only]
//   re = rere - imim, im = imre + reim           (CONJUGATED = 0)
//   re = rere + imim, im = imre - reim           (CONJUGATED = 1)
//        (AddSub, Full precision, ADD_LATENCY)
//   ab = {convert(re), convert(im)}  (Convert to N_BITS_AB/BIN_PT_AB with
//        QUANTIZATION/OVERFLOW, CONV_LATENCY)
//
//   latency = IN_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY
//             (+ PIPELINE_LATENCY, see above)
//
// The conjugated operand is b: with CONJUGATED = 1, re = a_re*b_re + a_im*b_im
// and im = a_im*b_re - a_re*b_im. cmult_init.m:44's comment ("conjugate the
// 'a' input") is wrong; the wiring is what counts. The conjugate is formed by
// the add/sub signs, not by negating b_im, so b_im = -2^(N_BITS_B-1) does not
// wrap.
//
// Complex words are {re, im} with the real part in the MSBs (bus_expand
// output 1 is the MSB slice; ri_to_c puts re in the MSBs). Both parts are
// signed with the port's binary point.
//
// Products and sums are exact (Xilinx Full precision: N_BITS_A+N_BITS_B and
// N_BITS_A+N_BITS_B+1 bits), so the output convert is the only rounding.
// The full-precision setting N_BITS_AB = N_BITS_A+N_BITS_B+1,
// BIN_PT_AB = BIN_PT_A+BIN_PT_B with CONV_LATENCY = 0 and IN_LATENCY = 0,
// CONJUGATED = 1 is bit- and cycle-equivalent to cmult_4bit_hdl*
// (system_145: real = ac + bd, imag = bc - ad, latency mult + add).
//
// Encodings:
//   QUANTIZATION              : 0 = Truncate, 1 = Round (unbiased: +/- Inf),
//                               2 = Round (unbiased: Even Values)
//   OVERFLOW                  : 0 = Wrap, 1 = Saturate
//   MULTIPLIER_IMPLEMENTATION : 0 = behavioral HDL, 1 = standard core,
//                               2 = embedded multiplier core
//   CONJUGATED, ASYNC, PIPELINED_ENABLE, PIPELINE_CMULT_EN, FLOATING_POINT:
//                               0 = off, 1 = on
//
// Defaults are the values stored in the casper_library mask, with one
// exception: the mask stores n_bits_a = 0, the empty-block shell value,
// which is illegal here ($fatal), so N_BITS_A uses the cmult_init.m default
// 18. PIPELINE_LATENCY = 0 is the mask-stored value (cmult_init.m's default
// is 2).
// Not implemented: FLOATING_POINT = 1 and ASYNC = 1 ($fatal). FLOAT_TYPE,
// EXP_WIDTH, FRAC_WIDTH and PIPELINED_ENABLE only matter for those modes and
// are declared only. MULTIPLIER_IMPLEMENTATION only selects the multiplier
// resource, except that it enables PIPELINE_CMULT_EN (embedded only).

module cmult #(
    parameter int    N_BITS_A                  = 18,
    parameter int    BIN_PT_A                  = 17,
    parameter int    N_BITS_B                  = 18,
    parameter int    BIN_PT_B                  = 17,
    parameter int    N_BITS_AB                 = 37,
    parameter int    BIN_PT_AB                 = 14,
    parameter int    QUANTIZATION              = 0,
    parameter int    OVERFLOW                  = 0,
    parameter int    FLOATING_POINT            = 0,
    parameter string FLOAT_TYPE                = "single",
    parameter int    EXP_WIDTH                 = 8,
    parameter int    FRAC_WIDTH                = 24,
    parameter int    MULT_LATENCY              = 3,
    parameter int    ADD_LATENCY               = 1,
    parameter int    CONV_LATENCY              = 1,
    parameter int    IN_LATENCY                = 0,
    parameter int    PIPELINE_CMULT_EN         = 0,
    parameter int    PIPELINE_LATENCY          = 0,
    parameter int    CONJUGATED                = 0,
    parameter int    ASYNC                     = 0,
    parameter int    PIPELINED_ENABLE          = 1,
    parameter int    MULTIPLIER_IMPLEMENTATION = 0
)(
    input  logic                     clk,
    input  logic [2*N_BITS_A-1:0]    a,
    input  logic [2*N_BITS_B-1:0]    b,
    output logic [2*N_BITS_AB-1:0]   ab
);

    initial begin
        if (N_BITS_A < 1 || N_BITS_B < 1)
            $fatal(1, "cmult: n_bits_a/n_bits_b = 0 (empty library block) is not supported");
        if (N_BITS_A < BIN_PT_A || N_BITS_B < BIN_PT_B || N_BITS_AB < BIN_PT_AB)
            $fatal(1, "cmult: number of bits must be >= binary point (cmult_init.m)");
        if (FLOATING_POINT != 0)
            $fatal(1, "cmult: FLOATING_POINT = 1 is not implemented");
        if (ASYNC != 0)
            $fatal(1, "cmult: ASYNC = 1 (en / dvalid ports) is not implemented");
        if (QUANTIZATION < 0 || QUANTIZATION > 2 || OVERFLOW < 0 || OVERFLOW > 1)
            $fatal(1, "cmult: invalid QUANTIZATION = %0d / OVERFLOW = %0d", QUANTIZATION, OVERFLOW);
    end

    // Full-precision product and sum formats (Xilinx Mult / AddSub, Full)
    localparam int NP  = N_BITS_A + N_BITS_B;
    localparam int BPP = BIN_PT_A + BIN_PT_B;
    localparam int NS  = NP + 1;
    // extra pipeline between the multipliers and the add/subs
    localparam int PIPE_LAT = (MULTIPLIER_IMPLEMENTATION == 2 && PIPELINE_CMULT_EN != 0)
                              ? PIPELINE_LATENCY : 0;

    // ── input latency (bus_replicate csp_latency) ────────────────────────────
    logic [2*N_BITS_A-1:0] a_d;
    logic [2*N_BITS_B-1:0] b_d;

    pipeline #(.BITWIDTH(2*N_BITS_A), .LATENCY(IN_LATENCY)) u_a_dly (
        .clk(clk), .din(a), .dout(a_d));
    pipeline #(.BITWIDTH(2*N_BITS_B), .LATENCY(IN_LATENCY)) u_b_dly (
        .clk(clk), .din(b), .dout(b_d));

    logic [N_BITS_A-1:0] a_re, a_im;
    logic [N_BITS_B-1:0] b_re, b_im;
    assign {a_re, a_im} = a_d;
    assign {b_re, b_im} = b_d;

    // ── four full-precision multipliers ──────────────────────────────────────
    logic [NP-1:0] rere, imim, imre, reim;

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(MULT_LATENCY)
    ) u_rere (.clk(clk), .a(a_re), .b(b_re), .dout(rere));

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(MULT_LATENCY)
    ) u_imim (.clk(clk), .a(a_im), .b(b_im), .dout(imim));

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(MULT_LATENCY)
    ) u_imre (.clk(clk), .a(a_im), .b(b_re), .dout(imre));

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(MULT_LATENCY)
    ) u_reim (.clk(clk), .a(a_re), .b(b_im), .dout(reim));

    // ── optional pipeline between multipliers and add/subs ───────────────────
    logic [NP-1:0] rere_p, imim_p, imre_p, reim_p;

    pipeline #(.BITWIDTH(4*NP), .LATENCY(PIPE_LAT)) u_prod_dly (
        .clk(clk), .din({rere, imim, imre, reim}),
        .dout({rere_p, imim_p, imre_p, reim_p}));

    // ── full-precision add/subs (conjugation selects the signs) ──────────────
    logic [NS-1:0] sum_re, sum_im;

    adder_subtractor #(
        .N_BITS_A(NP), .BIN_PT_A(BPP), .TYPE_A(1),
        .N_BITS_B(NP), .BIN_PT_B(BPP), .TYPE_B(1),
        .N_BITS_OUT(NS), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .OPMODE((CONJUGATED != 0) ? 0 : 1), .QUANTIZATION(0), .OVERFLOW(0),
        .LATENCY(ADD_LATENCY)
    ) u_addsub_re (.clk(clk), .a(rere_p), .b(imim_p), .dout(sum_re));

    adder_subtractor #(
        .N_BITS_A(NP), .BIN_PT_A(BPP), .TYPE_A(1),
        .N_BITS_B(NP), .BIN_PT_B(BPP), .TYPE_B(1),
        .N_BITS_OUT(NS), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .OPMODE((CONJUGATED != 0) ? 1 : 0), .QUANTIZATION(0), .OVERFLOW(0),
        .LATENCY(ADD_LATENCY)
    ) u_addsub_im (.clk(clk), .a(imre_p), .b(reim_p), .dout(sum_im));

    // ── output convert ───────────────────────────────────────────────────────
    logic [N_BITS_AB-1:0] ab_re, ab_im;

    convert #(
        .N_BITS_IN(NS), .BIN_PT_IN(BPP), .TYPE_IN(1),
        .N_BITS_OUT(N_BITS_AB), .BIN_PT_OUT(BIN_PT_AB), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .LATENCY(CONV_LATENCY)
    ) u_convert_re (.clk(clk), .din(sum_re), .dout(ab_re));

    convert #(
        .N_BITS_IN(NS), .BIN_PT_IN(BPP), .TYPE_IN(1),
        .N_BITS_OUT(N_BITS_AB), .BIN_PT_OUT(BIN_PT_AB), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .LATENCY(CONV_LATENCY)
    ) u_convert_im (.clk(clk), .din(sum_im), .dout(ab_im));

    // ri_to_c: real part in the MSBs
    assign ab = {ab_re, ab_im};

endmodule
