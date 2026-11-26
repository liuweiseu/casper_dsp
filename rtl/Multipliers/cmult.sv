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
// ASYNC = 1 (casper async, en / dvalid): see the async block below; it
// follows cmult_init.m, except that dvalid is aligned with ab (mlib_devel
// bug 13 fixed, see PIPELINED_ENABLE).
// Not implemented: FLOATING_POINT = 1 ($fatal). FLOAT_TYPE, EXP_WIDTH and
// FRAC_WIDTH only matter for that mode and are declared only. MULTIPLIER_IMPLEMENTATION only selects the multiplier
// resource, except that it enables PIPELINE_CMULT_EN (embedded only).
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
// block = 'casper_library_multipliers.slx/cmult'
// deviations = [
//   'FLOATING_POINT = 1 is not implemented ($fatal); FLOAT_TYPE, EXP_WIDTH and FRAC_WIDTH are declared only. ASYNC = 1 together with the embedded-multiplier pipeline (MULTIPLIER_IMPLEMENTATION = 2, PIPELINE_CMULT_EN = 1) is not implemented either ($fatal): how that pipeline is enabled was not checked against Simulink.',
//   "OVERFLOW = 2 ('Flag as error') is a $fatal; in Simulink the output Convert raises a simulation error on overflow and the generated hardware wraps.",
//   "Default N_BITS_A = 18 differs from the mask-stored n_bits_a = 0 (empty-block shell value, illegal in the HDL), and the mask-stored pipeline_latency = 0 differs from cmult_init.m's default 2; only the stored values matter when instantiating from the library.",
//   "The output Convert rounding/saturation is the Bus/convert module (see its deviations); products and sums are full precision as in cmult_init.m (Mult/AddSub 'precision' = 'Full').",
//   "ASYNC = 1, PIPELINED_ENABLE = 1: dvalid = en delayed IN + MULT + ADD + CONV latency, aligned with ab (intended behaviour). Simulink delays it by IN + MULT + 2*ADD because casper's den Delay takes the add latency (mlib_devel bug 13, docs/bugs.md), so dvalid differs when CONV_LATENCY != ADD_LATENCY; ab is unaffected.",
// ]
//
// [params.QUANTIZATION]
// mask = 'quantization'
// type = 'popup'
// [params.QUANTIZATION.values]
// 0 = 'Truncate'
// 1 = 'Round  (unbiased: +/- Inf)'
// 2 = 'Round  (unbiased: Even Values)'
//
// [params.OVERFLOW]
// mask = 'overflow'
// type = 'popup'
// hdl_unsupported = [2]
// note = 'OVERFLOW 2 is rejected by the HDL ($fatal)'
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Flag as error'
//
// [params.CONJUGATED]
// mask = 'conjugated'
// type = 'checkbox'
// [params.CONJUGATED.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// note = 'async = on: en gates every Mult / AddSub / Convert latency chain; dvalid with pipelined_enable = on only (see PIPELINED_ENABLE). Matches Simulink (MATLAB R2021a, async batch 1) except the dvalid latency when conv_latency != add_latency (bug 13, see PIPELINED_ENABLE). The HDL ports always exist, dvalid = 0 when there is none'
// [params.ASYNC.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.PIPELINED_ENABLE]
// mask = 'pipelined_enable'
// type = 'checkbox'
// note = "only used with async = on. on: each stage is gated by en delayed to its input (in, mult, add latency) and dvalid = en delayed in + mult + add + conv latency, aligned with ab. casper's den Delay takes the add latency instead of conv_latency (cmult_init.m:532-535, 623-627; mlib_devel bug 13), so Simulink's dvalid is in + mult + 2*add; the HDL implements the intended behaviour and differs from Simulink when CONV_LATENCY != ADD_LATENCY (those sets are excluded from the Simulink comparison). off: every stage is gated by the raw en, in_latency is forced to 0 and there is no dvalid"
// [params.PIPELINED_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FLOATING_POINT]
// mask = 'floating_point'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = 'FLOATING_POINT 1 is rejected by the HDL ($fatal)'
// [params.FLOATING_POINT.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FLOAT_TYPE]
// mask = 'float_type'
// type = 'popup'
// note = 'mask radiobutton; HDL string parameter, declared only (floating point not implemented)'
// [params.FLOAT_TYPE.values]
// single = 'single'
// custom = 'custom'
//
// [params.MULTIPLIER_IMPLEMENTATION]
// mask = 'multiplier_implementation'
// type = 'popup'
// [params.MULTIPLIER_IMPLEMENTATION.values]
// 0 = 'behavioral HDL'
// 1 = 'standard core'
// 2 = 'embedded multiplier core'
//
// [params.PIPELINE_CMULT_EN]
// mask = 'pipeline_cmult_en'
// type = 'checkbox'
// [params.PIPELINE_CMULT_EN.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// order = 'Simulink: a, b, en (async only) -> ab, dvalid (async and pipelined_enable only) (checked on a built block); HDL: the same order'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

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
    input  logic                     en = 1'b1,
    output logic [2*N_BITS_AB-1:0]   ab,
    output logic                     dvalid
);

    initial begin
        if (N_BITS_A < 1 || N_BITS_B < 1)
            $fatal(1, "cmult: n_bits_a/n_bits_b = 0 (empty library block) is not supported");
        if (N_BITS_A < BIN_PT_A || N_BITS_B < BIN_PT_B || N_BITS_AB < BIN_PT_AB)
            $fatal(1, "cmult: number of bits must be >= binary point (cmult_init.m)");
        if (FLOATING_POINT != 0)
            $fatal(1, "cmult: FLOATING_POINT = 1 is not implemented");
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

    if (ASYNC != 0 && PIPE_LAT != 0)
        $fatal(1, "cmult: ASYNC = 1 with the embedded-multiplier pipeline (PIPELINE_CMULT_EN) is not implemented");

    // ── async (cmult_init.m:168-172, 220-231, 406-426, 519-547, 604-651) ─────
    // Every Xilinx Mult / AddSub / Convert gets an en port, and its whole
    // latency chain only advances while that en is 1. With PIPELINED_ENABLE
    // each stage gets en delayed to its own input (en_replicate0/1/2: e1 =
    // en delayed IN_LATENCY, e2 = e1 delayed MULT_LATENCY, e3 = e2 delayed
    // ADD_LATENCY) and dvalid = e3 delayed again; without it every stage
    // gets the raw en, the input latency is forced to 0 (:177-178) and there
    // is no dvalid. dvalid = e3 delayed CONV_LATENCY, aligned with ab. casper's
    // den Delay is created with the add latency still in 'latency'
    // (:532-535, 623-627; mlib_devel bug 13); the HDL does not reproduce it.
    localparam bit ASY = (ASYNC != 0);
    localparam bit PEN = ASY && (PIPELINED_ENABLE != 0);
    localparam int IN_LAT = (ASY && !PEN) ? 0 : IN_LATENCY;
    // the gated stages are delays after a latency-0 Mult / Convert
    localparam int MULT_LAT_HW = ASY ? 0 : MULT_LATENCY;
    localparam int CONV_LAT_HW = ASY ? 0 : CONV_LATENCY;

    logic e1, e2, e3;

    generate
        if (PEN) begin : GEN_EN_PIPE
            pipeline #(.BITWIDTH(1), .CSP_LATENCY(IN_LATENCY))   u_e1 (.clk(clk), .din(en), .dout(e1));
            pipeline #(.BITWIDTH(1), .CSP_LATENCY(MULT_LATENCY)) u_e2 (.clk(clk), .din(e1), .dout(e2));
            pipeline #(.BITWIDTH(1), .CSP_LATENCY(ADD_LATENCY))  u_e3 (.clk(clk), .din(e2), .dout(e3));
            pipeline #(.BITWIDTH(1), .CSP_LATENCY(CONV_LATENCY)) u_den (.clk(clk), .din(e3), .dout(dvalid));
        end else begin : GEN_EN_RAW
            assign e1 = en;
            assign e2 = en;
            assign e3 = en;
            assign dvalid = 1'b0;
        end
    endgenerate

    // ── input latency (bus_replicate csp_latency) ────────────────────────────
    logic [2*N_BITS_A-1:0] a_d;
    logic [2*N_BITS_B-1:0] b_d;

    pipeline #(.BITWIDTH(2*N_BITS_A), .CSP_LATENCY(IN_LAT)) u_a_dly (
        .clk(clk), .din(a), .dout(a_d));
    pipeline #(.BITWIDTH(2*N_BITS_B), .CSP_LATENCY(IN_LAT)) u_b_dly (
        .clk(clk), .din(b), .dout(b_d));

    logic [N_BITS_A-1:0] a_re, a_im;
    logic [N_BITS_B-1:0] b_re, b_im;
    assign {a_re, a_im} = a_d;
    assign {b_re, b_im} = b_d;

    // ── four full-precision multipliers ──────────────────────────────────────
    logic [NP-1:0] rere_m, imim_m, imre_m, reim_m;
    logic [NP-1:0] rere, imim, imre, reim;

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LAT_HW)
    ) u_rere (.clk(clk), .a(a_re), .b(b_re), .dout(rere_m), .misco());

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LAT_HW)
    ) u_imim (.clk(clk), .a(a_im), .b(b_im), .dout(imim_m), .misco());

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LAT_HW)
    ) u_imre (.clk(clk), .a(a_im), .b(b_re), .dout(imre_m), .misco());

    multiplier #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .TYPE_A(1),
        .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B), .TYPE_B(1),
        .N_BITS_OUT(NP), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LAT_HW)
    ) u_reim (.clk(clk), .a(a_re), .b(b_im), .dout(reim_m), .misco());

    generate
        if (ASY) begin : GEN_MULT_STALL
            delay #(.LATENCY(MULT_LATENCY), .BITWIDTH(4*NP), .USE_ENABLE(1)) u_mult_chain (
                .clk(clk), .din({rere_m, imim_m, imre_m, reim_m}), .en(e1),
                .dout({rere, imim, imre, reim}));
        end else begin : GEN_MULT_FREE
            assign {rere, imim, imre, reim} = {rere_m, imim_m, imre_m, reim_m};
        end
    endgenerate

    // ── optional pipeline between multipliers and add/subs ───────────────────
    logic [NP-1:0] rere_p, imim_p, imre_p, reim_p;

    pipeline #(.BITWIDTH(4*NP), .CSP_LATENCY(PIPE_LAT)) u_prod_dly (
        .clk(clk), .din({rere, imim, imre, reim}),
        .dout({rere_p, imim_p, imre_p, reim_p}));

    // ── full-precision add/subs (conjugation selects the signs) ──────────────
    logic [NS-1:0] sum_re, sum_im;

    adder_subtractor #(
        .N_BITS_A(NP), .BIN_PT_A(BPP), .TYPE_A(1),
        .N_BITS_B(NP), .BIN_PT_B(BPP), .TYPE_B(1),
        .N_BITS_OUT(NS), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .OPMODE((CONJUGATED != 0) ? 0 : 1), .QUANTIZATION(0), .OVERFLOW(0),
        .CSP_LATENCY(ADD_LATENCY), .ASYNC(int'(ASY))
    ) u_addsub_re (.clk(clk), .a(rere_p), .b(imim_p), .en(e2), .dout(sum_re), .misco(), .dvalid());

    adder_subtractor #(
        .N_BITS_A(NP), .BIN_PT_A(BPP), .TYPE_A(1),
        .N_BITS_B(NP), .BIN_PT_B(BPP), .TYPE_B(1),
        .N_BITS_OUT(NS), .BIN_PT_OUT(BPP), .TYPE_OUT(1),
        .OPMODE((CONJUGATED != 0) ? 1 : 0), .QUANTIZATION(0), .OVERFLOW(0),
        .CSP_LATENCY(ADD_LATENCY), .ASYNC(int'(ASY))
    ) u_addsub_im (.clk(clk), .a(imre_p), .b(reim_p), .en(e2), .dout(sum_im), .misco(), .dvalid());

    // ── output convert ───────────────────────────────────────────────────────
    logic [N_BITS_AB-1:0] ab_re_c, ab_im_c, ab_re, ab_im;

    convert #(
        .N_BITS_IN(NS), .BIN_PT_IN(BPP), .TYPE_IN(1),
        .N_BITS_OUT(N_BITS_AB), .BIN_PT_OUT(BIN_PT_AB), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CONV_LAT_HW)
    ) u_convert_re (.clk(clk), .din(sum_re), .dout(ab_re_c), .overflow(), .misco());

    convert #(
        .N_BITS_IN(NS), .BIN_PT_IN(BPP), .TYPE_IN(1),
        .N_BITS_OUT(N_BITS_AB), .BIN_PT_OUT(BIN_PT_AB), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CONV_LAT_HW)
    ) u_convert_im (.clk(clk), .din(sum_im), .dout(ab_im_c), .overflow(), .misco());

    generate
        if (ASY) begin : GEN_CONV_STALL
            delay #(.LATENCY(CONV_LATENCY), .BITWIDTH(2*N_BITS_AB), .USE_ENABLE(1)) u_conv_chain (
                .clk(clk), .din({ab_re_c, ab_im_c}), .en(e3), .dout({ab_re, ab_im}));
        end else begin : GEN_CONV_FREE
            assign {ab_re, ab_im} = {ab_re_c, ab_im_c};
        end
    endgenerate

    // ri_to_c: real part in the MSBs
    assign ab = {ab_re, ab_im};

endmodule
