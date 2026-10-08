// butterfly_direct — radix-2 butterfly: (a + b·w, a − b·w), with shift and
// overflow flag
//
// Corresponds to casper_library's butterfly_direct (fixed-point, synchronous
// path), built as butterfly_direct_init.m draws it:
//
//   a, b, sync ─► twiddle_* ─► ao, bwo ─► adder_subtractor (a+bw, a−bw; exact)
//      ─► [ shift / scale stage, see SHIFTING ] ─► convert_of ─► apbw, ambw
//                                                   └─► of (per lane, +1 cycle)
//
// TWIDDLE SELECTION (generate; the rule of butterfly_direct_init.m, from
// casper's Coeffs list, here given as N_COEFFS / COEFF_0 = Coeffs(1) /
// COEFF_1 = Coeffs(2)):
//   N_COEFFS = 1, COEFF_0 = 0 : twiddle_pass_through (BIPLEX = 1)
//                               twiddle_coeff_0      (BIPLEX = 0)
//   N_COEFFS = 1, COEFF_0 = 1 : twiddle_coeff_1
//   N_COEFFS = 2, COEFFS = [0 1], STEP_PERIOD = FFT_SIZE-2 : twiddle_stage_2
//   anything else             : twiddle_general (table from INIT_FILE, made by
//                               rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py for Coeffs)
//
// WIDTHS (butterfly_direct_init.m): the adders take a (INPUT_BIT_WIDTH,
// BIN_PT_IN) and bwo, which is INPUT_BIT_WIDTH+1 bits for twiddle_general and
// INPUT_BIT_WIDTH bits for the other variants; the exact sum / difference is
// one bit wider than bwo (BIN_PT_IN).
//
// SHIFTING:
//   BITGROWTH = 1          : no shift; outputs INPUT_BIT_WIDTH+1 bits
//   HARDCODE_SHIFTS = 1    : static; DOWNSHIFT = 1 halves the result
//   otherwise (default)    : dynamic; shift = 1 halves the result. shift
//                            passes through FAN_LATENCY registers (casper's
//                            bus_replicate) and selects between the unscaled
//                            and halved sums in a 1-cycle mux, so the mux
//                            uses shift from FAN_LATENCY cycles before the
//                            sum reaches it.
//   The final convert_of rounds to BIN_PT_IN (QUANTIZATION) and handles
//   overflow (OVERFLOW) of the output format; outputs are INPUT_BIT_WIDTH
//   bits unless BITGROWTH = 1.
//
// OVERFLOW FLAG: of[n] = 1 when any of lane n's four output components
// (re / im of a+bw and a−bw) overflowed in convert_of; one cycle after the
// data (casper's bus_relational, latency 1).
//
// LATENCY (data and sync_out) = TWIDDLE_LATENCY + ADD_LATENCY + MUX_LATENCY +
// CONV_LATENCY, MUX_LATENCY = 1 for dynamic shifting, 0 otherwise; of comes
// one cycle later.
//
// Declared for traceability only (not implemented in v1): ASYNC and
// FLOATING_POINT must be 0; FLOAT_TYPE, EXP_WIDTH, FRAC_WIDTH,
// ADD_PIPE_LATENCY, MULT_PIPE_LATENCY, COEFFS_BIT_LIMIT, COEFF_SHARING,
// COEFF_DECIMATION, COEFF_GENERATION, CAL_BITS, N_BITS_ROTATION, USE_HDL,
// USE_EMBEDDED and DSP48_ADDERS are ignored (MAX_FANOUT only sets
// FAN_LATENCY). COEFFS_BRAM is covered by rom's PLATFORM.
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
// block = 'casper_library_ffts.slx/butterfly_direct'
// deviations = [
//   "The mask's bin_pt_in = -1 backwards-compatibility value (replaced by input_bit_width-1 in butterfly_direct_init.m:178-182) is not recognised: BIN_PT_IN must be given explicitly.",
//   "OVERFLOW = 2 ('Error') has no working Simulink counterpart: butterfly_direct_init.m:512-514 compares the option against 'Flag as error', so 'Error' leaves the bus_convert overflow argument undefined and the mask init fails, whereas the HDL silently wraps (rtl/Bus/convert.sv saturates only for OVERFLOW = 1).",
//   "DSP48_ADDERS is ignored, but in Simulink dsp48_adders = 'on' forces add_latency = 2 in every butterfly_direct (butterfly_direct_init.m:194-197), so with the box ticked and ADD_LATENCY != 2 the Simulink data/sync latency differs from the HDL's.",
//   "ADD_PIPE_LATENCY / MULT_PIPE_LATENCY are ignored: in Simulink a non-zero add_pipe_latency inserts pipeline blocks on the bus_addsub inputs (bus_addsub_init.m:250-275, enabled by butterfly_direct_init.m:156-160) and mult_pipe_latency pipelines twiddle_general's bus_mult (twiddle_general_init.m:250-251), so for non-zero values the HDL has less latency (note Simulink's own fixed-point sync delay, butterfly_direct_init.m:652, does not include add_pipe_latency); only 0 is equivalent.",
//   "COEFF_GENERATION / CAL_BITS / N_BITS_ROTATION are ignored and the twiddle is always a ROM table, but with coeff_generation = 'on' (mask default) casper's twiddle_general -> coeff_gen uses a feedback_osc oscillator instead of a table for a bit-reversed Coeffs list with log2(length(Coeffs)) > ceil(log2(mult_latency+add_latency+conv_latency+1)) + cal_bits (coeff_gen_init.m:260, 308, 497-530), whose values are not the exactly rounded table values (fft_stage_n passes coeff_generation = 'off', fft_stage_n_init.m:501, so biplex use is unaffected).",
//   "A single-coefficient twiddle_general (coefficient index other than 0 or 1) is a constant in casper quantized to coeff_bit_width-2 fraction bits (coeff_gen_init.m:156-157, stored as Fix_<cbw>_<cbw-1>), while the HDL's table (rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py:52) uses coeff_bit_width-1 fraction bits, so that twiddle (and the products) can differ by one coefficient LSB; known and left unchanged (mlib_devel_notes/fft_wideband_real_hdl_plan.md Phase 6).",
//   'The Coeffs vector is replaced by N_COEFFS / COEFF_0 / COEFF_1 (twiddle selection) plus an INIT_FILE table that must be generated separately for the same Coeffs; a wrong or missing file silently gives wrong twiddles (Simulink computes them from Coeffs at init).',
//   'Bit order of of: the HDL puts lane 0 in bit 0 (of[n] = lane n), but Simulink packs the per-lane flags with bus_create/Concat, lane 0 in the MSB (butterfly_direct_init.m:625-643 munge + bus_relational -> bussify in1 = MSB, bus_relational_init.m:194); the vector is bit-reversed relative to Simulink when it has more than one bit (fft_wideband_real.sv:31-33 and its GEN_OF loop undo this for the top-level of).',
// ]
//
// [params.BIPLEX]
// mask = 'biplex'
// type = 'checkbox'
// [params.BIPLEX.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.BITGROWTH]
// mask = 'bitgrowth'
// type = 'checkbox'
// [params.BITGROWTH.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.DOWNSHIFT]
// mask = 'downshift'
// type = 'checkbox'
// [params.DOWNSHIFT.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.HARDCODE_SHIFTS]
// mask = 'hardcode_shifts'
// type = 'checkbox'
// [params.HARDCODE_SHIFTS.values]
// 0 = 'off'
// 1 = 'on'
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
// note = "the HDL treats 2 as wrap (rtl/Bus/convert.sv saturates only for 1); in Simulink 'Error' does not build (butterfly_direct_init.m:512-514 tests for 'Flag as error')"
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Error'
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = '$fatal unless 0 (en/dvalid handshake not implemented)'
// [params.ASYNC.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FLOATING_POINT]
// mask = 'floating_point'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = '$fatal unless 0 (fixed point only)'
// [params.FLOATING_POINT.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FLOAT_TYPE]
// mask = 'float_type'
// type = 'popup'
// note = 'radiobutton; the init scripts test float_type == 2 (1-based option index); ignored (FLOATING_POINT must be 0)'
// [params.FLOAT_TYPE.values]
// 1 = 'single'
// 2 = 'custom'
//
// [params.COEFF_SHARING]
// mask = 'coeff_sharing'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL'
// [params.COEFF_SHARING.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.COEFF_DECIMATION]
// mask = 'coeff_decimation'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL'
// [params.COEFF_DECIMATION.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.COEFF_GENERATION]
// mask = 'coeff_generation'
// type = 'checkbox'
// note = 'ignored: the HDL always reads a ROM table (see deviations)'
// [params.COEFF_GENERATION.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_HDL]
// mask = 'use_hdl'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL (multiplier implementation only)'
// [params.USE_HDL.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_EMBEDDED]
// mask = 'use_embedded'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL (multiplier implementation only)'
// [params.USE_EMBEDDED.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.DSP48_ADDERS]
// mask = 'dsp48_adders'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL (see deviations: Simulink forces add_latency = 2)'
// [params.DSP48_ADDERS.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FFT_SIZE]
// mask = 'FFTSize'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [params.STEP_PERIOD]
// mask = 'StepPeriod'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [hdl_only]
// N_COEFFS = "length(Coeffs): replaces the mask's vector Coeffs"
// COEFF_0 = "Coeffs(1): replaces the mask's vector Coeffs"
// COEFF_1 = "Coeffs(2): replaces the mask's vector Coeffs"
// INIT_FILE = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// N_BITS_OUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
// Coeffs = 'vector parameter: replaced by N_COEFFS and the coefficient file'
//
// [ports]
// note = 'each Simulink complex port x is split into x_re / x_im; the Simulink names are not legal HDL identifiers; the Simulink a, b, a+bw, a-bw buses carry N_INPUTS complex lanes, lane 0 in the MSBs, which become array element 0'
// [ports.renamed]
// apbw_re = 'a+bw'
// apbw_im = 'a+bw'
// ambw_re = 'a-bw'
// ambw_im = 'a-bw'
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module butterfly_direct #(
    parameter int    N_INPUTS          = 1,
    parameter int    BIPLEX            = 1,
    parameter int    FFT_SIZE          = 6,
    parameter int    N_COEFFS          = 32,
    parameter int    COEFF_0           = 0,
    parameter int    COEFF_1           = 16,
    parameter int    STEP_PERIOD       = 1,
    parameter string INIT_FILE         = "",
    parameter int    COEFF_BIT_WIDTH   = 18,
    parameter int    INPUT_BIT_WIDTH   = 18,
    parameter int    BIN_PT_IN         = 17,
    parameter int    BITGROWTH         = 0,
    parameter int    DOWNSHIFT         = 0,
    parameter int    HARDCODE_SHIFTS   = 0,
    parameter int    ADD_LATENCY       = 1,
    parameter int    MULT_LATENCY      = 2,
    parameter int    BRAM_LATENCY      = 1,
    parameter int    CONV_LATENCY      = 1,
    parameter int    QUANTIZATION      = 0,
    parameter int    OVERFLOW          = 0,
    parameter int    MAX_FANOUT        = 4,
    parameter string PLATFORM          = "GENERIC",
    // declared, not implemented (see header)
    parameter int    ASYNC             = 0,
    parameter int    FLOATING_POINT    = 0,
    parameter int    FLOAT_TYPE        = 1,
    parameter int    EXP_WIDTH         = 6,
    parameter int    FRAC_WIDTH        = 25,
    parameter int    ADD_PIPE_LATENCY  = 0,
    parameter int    MULT_PIPE_LATENCY = 0,
    parameter int    COEFFS_BIT_LIMIT  = 8,
    parameter int    COEFF_SHARING     = 1,
    parameter int    COEFF_DECIMATION  = 1,
    parameter int    COEFF_GENERATION  = 1,
    parameter int    CAL_BITS          = 1,
    parameter int    N_BITS_ROTATION   = 25,
    parameter int    USE_HDL           = 0,
    parameter int    USE_EMBEDDED      = 0,
    parameter int    DSP48_ADDERS      = 0,
    // output width, derived (not meant to be overridden)
    parameter int    N_BITS_OUT        = (BITGROWTH != 0) ? INPUT_BIT_WIDTH + 1 : INPUT_BIT_WIDTH
)(
    input  logic                       clk,
    input  logic [INPUT_BIT_WIDTH-1:0] a_re    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] a_im    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] b_re    [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] b_im    [N_INPUTS],
    input  logic                       sync_in,
    input  logic                       shift,
    output logic [N_BITS_OUT-1:0]      apbw_re [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      apbw_im [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      ambw_re [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      ambw_im [N_INPUTS],
    output logic [N_INPUTS-1:0]        of,
    output logic                       sync_out
);

    // ── twiddle selection (butterfly_direct_init.m) ──────────────────────────
    localparam int TW_PASS_THROUGH = 0;
    localparam int TW_COEFF_0      = 1;
    localparam int TW_COEFF_1      = 2;
    localparam int TW_STAGE_2      = 3;
    localparam int TW_GENERAL      = 4;

    localparam int TWIDDLE_TYPE =
        (N_COEFFS == 1 && COEFF_0 == 0) ? ((BIPLEX != 0) ? TW_PASS_THROUGH : TW_COEFF_0) :
        (N_COEFFS == 1 && COEFF_0 == 1) ? TW_COEFF_1 :
        (N_COEFFS == 2 && COEFF_0 == 0 && COEFF_1 == 1 && STEP_PERIOD == FFT_SIZE - 2) ? TW_STAGE_2 :
                                          TW_GENERAL;

    // A single-coefficient twiddle_general is a constant in casper (coeff_gen
    // without a table), with the 1+mult+add+conv latency of twiddle_coeff_0
    // ("must match twiddle_general with single coefficient so that latencies
    // match when used in fft_direct", twiddle_coeff_0_init.m): its coefficient
    // read latency is 1 here, whatever BRAM_LATENCY is.
    localparam int TW_BRAM_LATENCY = (N_COEFFS == 1) ? 1 : BRAM_LATENCY;

    localparam int TWIDDLE_LATENCY =
        (TWIDDLE_TYPE == TW_PASS_THROUGH) ? 0 :
        (TWIDDLE_TYPE == TW_COEFF_0 || TWIDDLE_TYPE == TW_COEFF_1)
            ? 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY
            : TW_BRAM_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY;

    localparam int DYNAMIC     = (BITGROWTH == 0 && HARDCODE_SHIFTS == 0) ? 1 : 0;
    localparam int MUX_LATENCY = DYNAMIC;
    localparam int LATENCY     = TWIDDLE_LATENCY + ADD_LATENCY + MUX_LATENCY + CONV_LATENCY;

    // casper bus_replicate latency for the shift select
    localparam int FAN_RATIO   = (N_INPUTS * 4 + MAX_FANOUT - 1) / MAX_FANOUT;
    localparam int FAN_LATENCY = ($clog2(FAN_RATIO) > 1) ? $clog2(FAN_RATIO) : 1;

    // adder widths
    localparam int IW          = INPUT_BIT_WIDTH;
    localparam int BP          = BIN_PT_IN;
    localparam int BW_W        = (TWIDDLE_TYPE == TW_GENERAL) ? IW + 1 : IW;   // addsub_b_bitwidth
    localparam int SUM_W       = BW_W + 1;                                     // n_bits_addsub_out
    // convert input format
    localparam int CONV_IN_W   = (DYNAMIC != 0) ? SUM_W + 1 : SUM_W;
    localparam int CONV_IN_BP  = (DYNAMIC != 0 || (HARDCODE_SHIFTS != 0 && DOWNSHIFT != 0 && BITGROWTH == 0))
                                 ? BP + 1 : BP;

    if (ASYNC != 0)          $fatal(1, "butterfly_direct: ASYNC is not implemented");
    if (FLOATING_POINT != 0) $fatal(1, "butterfly_direct: FLOATING_POINT is not implemented");

    // ── twiddle ──────────────────────────────────────────────────────────────
    logic [IW-1:0]   ao_re  [N_INPUTS], ao_im  [N_INPUTS];
    logic [BW_W-1:0] bwo_re [N_INPUTS], bwo_im [N_INPUTS];
    logic            tw_sync;

    generate
        if (TWIDDLE_TYPE == TW_PASS_THROUGH) begin : GEN_TW_PASS
            twiddle_pass_through #(
                .N_INPUTS(N_INPUTS), .INPUT_BIT_WIDTH(IW)
            ) u_twiddle (
                .clk(clk), .ai_re(a_re), .ai_im(a_im), .bi_re(b_re), .bi_im(b_im),
                .sync_in(sync_in), .ao_re(ao_re), .ao_im(ao_im),
                .bwo_re(bwo_re), .bwo_im(bwo_im), .sync_out(tw_sync));
        end else if (TWIDDLE_TYPE == TW_COEFF_0) begin : GEN_TW_COEFF_0
            twiddle_coeff_0 #(
                .N_INPUTS(N_INPUTS), .INPUT_BIT_WIDTH(IW),
                .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
                .BRAM_LATENCY(BRAM_LATENCY), .CONV_LATENCY(CONV_LATENCY)
            ) u_twiddle (
                .clk(clk), .ai_re(a_re), .ai_im(a_im), .bi_re(b_re), .bi_im(b_im),
                .sync_in(sync_in), .ao_re(ao_re), .ao_im(ao_im),
                .bwo_re(bwo_re), .bwo_im(bwo_im), .sync_out(tw_sync));
        end else if (TWIDDLE_TYPE == TW_COEFF_1) begin : GEN_TW_COEFF_1
            twiddle_coeff_1 #(
                .N_INPUTS(N_INPUTS), .INPUT_BIT_WIDTH(IW), .BIN_PT_IN(BP),
                .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
                .BRAM_LATENCY(BRAM_LATENCY), .CONV_LATENCY(CONV_LATENCY)
            ) u_twiddle (
                .clk(clk), .ai_re(a_re), .ai_im(a_im), .bi_re(b_re), .bi_im(b_im),
                .sync_in(sync_in), .ao_re(ao_re), .ao_im(ao_im),
                .bwo_re(bwo_re), .bwo_im(bwo_im), .sync_out(tw_sync));
        end else if (TWIDDLE_TYPE == TW_STAGE_2) begin : GEN_TW_STAGE_2
            twiddle_stage_2 #(
                .N_INPUTS(N_INPUTS), .FFT_SIZE(FFT_SIZE), .INPUT_BIT_WIDTH(IW),
                .BIN_PT_IN(BP), .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY),
                .BRAM_LATENCY(BRAM_LATENCY), .CONV_LATENCY(CONV_LATENCY)
            ) u_twiddle (
                .clk(clk), .ai_re(a_re), .ai_im(a_im), .bi_re(b_re), .bi_im(b_im),
                .sync_in(sync_in), .ao_re(ao_re), .ao_im(ao_im),
                .bwo_re(bwo_re), .bwo_im(bwo_im), .sync_out(tw_sync));
        end else begin : GEN_TW_GENERAL
            twiddle_general #(
                .N_INPUTS(N_INPUTS), .FFT_SIZE(FFT_SIZE), .N_COEFFS(N_COEFFS),
                .STEP_PERIOD(STEP_PERIOD), .INPUT_BIT_WIDTH(IW), .BIN_PT_IN(BP),
                .COEFF_BIT_WIDTH(COEFF_BIT_WIDTH), .MULT_LATENCY(MULT_LATENCY),
                .ADD_LATENCY(ADD_LATENCY), .CONV_LATENCY(CONV_LATENCY),
                .BRAM_LATENCY(TW_BRAM_LATENCY), .QUANTIZATION(QUANTIZATION),
                .OVERFLOW(OVERFLOW), .INIT_FILE(INIT_FILE), .PLATFORM(PLATFORM)
            ) u_twiddle (
                .clk(clk), .ai_re(a_re), .ai_im(a_im), .bi_re(b_re), .bi_im(b_im),
                .sync_in(sync_in), .ao_re(ao_re), .ao_im(ao_im),
                .bwo_re(bwo_re), .bwo_im(bwo_im), .sync_out(tw_sync));
        end
    endgenerate

    // ── shift select (dynamic shifting only) ─────────────────────────────────
    logic shift_d;

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(FAN_LATENCY)) u_shift_dly (
        .clk(clk), .din(shift), .dout(shift_d));

    // ── per lane: add / subtract, shift, convert ─────────────────────────────
    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        // component c: 0 = (a+bw).re, 1 = (a+bw).im, 2 = (a−bw).re, 3 = (a−bw).im
        logic [IW-1:0]         a_c   [4];
        logic [BW_W-1:0]       b_c   [4];
        logic [N_BITS_OUT-1:0] out_c [4];
        logic [3:0]            of_c;

        assign a_c = '{ao_re[n], ao_im[n], ao_re[n], ao_im[n]};
        assign b_c = '{bwo_re[n], bwo_im[n], bwo_re[n], bwo_im[n]};

        for (genvar c = 0; c < 4; c++) begin : GEN_COMP
            // per-component signals (whole arrays here would make Verilator
            // see a false combinational loop when the shift stage is a wire)
            logic [SUM_W-1:0]     sum_c;
            logic [CONV_IN_W-1:0] cin_c;

            adder_subtractor #(
                .N_BITS_A(IW),    .BIN_PT_A(BP), .TYPE_A(1),
                .N_BITS_B(BW_W),  .BIN_PT_B(BP), .TYPE_B(1),
                .N_BITS_OUT(SUM_W), .BIN_PT_OUT(BP), .TYPE_OUT(1),
                .OPMODE(c / 2), .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(ADD_LATENCY)
            ) u_addsub (.clk(clk), .a(a_c[c]), .b(b_c[c]), .dout(sum_c));

            if (DYNAMIC != 0) begin : GEN_DYNAMIC
                // unscaled (bus_norm0) and halved (bus_scale + bus_norm1), both
                // exact in (SUM_W+1, BP+1); a 1-cycle mux picks one
                logic [CONV_IN_W-1:0] norm0, norm1;
                convert #(
                    .N_BITS_IN(SUM_W), .BIN_PT_IN(BP), .TYPE_IN(1),
                    .N_BITS_OUT(CONV_IN_W), .BIN_PT_OUT(BP + 1), .TYPE_OUT(1),
                    .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(0)
                ) u_norm0 (.clk(clk), .din(sum_c), .dout(norm0));
                scale #(
                    .N_BITS_IN(SUM_W), .BIN_PT_IN(BP), .TYPE_IN(1), .SCALE_FACTOR(-1),
                    .N_BITS_OUT(CONV_IN_W), .BIN_PT_OUT(BP + 1), .TYPE_OUT(1),
                    .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(0)
                ) u_norm1 (.clk(clk), .din(sum_c), .dout(norm1));
                multiplexer #(.NBITS(CONV_IN_W), .NINPUTS(2), .LATENCY(MUX_LATENCY)) u_mux (
                    .clk(clk), .din('{norm0, norm1}), .sel(shift_d), .dout(cin_c));
            end else begin : GEN_STATIC
                // bitgrowth, or hardcoded shift: DOWNSHIFT only moves the
                // binary point (CONV_IN_BP), the bits are unchanged
                assign cin_c = sum_c;
            end

            convert_of #(
                .BIT_WIDTH_I (CONV_IN_W),  .BINARY_POINT_I (CONV_IN_BP),
                .BIT_WIDTH_O(N_BITS_OUT), .BINARY_POINT_O(BP),
                .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CONV_LATENCY)
            ) u_convert (.clk(clk), .din(cin_c), .dout(out_c[c]), .of(of_c[c]));
        end

        assign apbw_re[n] = out_c[0];
        assign apbw_im[n] = out_c[1];
        assign ambw_re[n] = out_c[2];
        assign ambw_im[n] = out_c[3];

        // any component overflowed (casper: munge + bus_relational a!=0, latency 1)
        logical #(.NBITS(1), .NINPUTS(4), .LATENCY(1), .FUNC(2)) u_of_or (
            .clk(clk), .din('{of_c[0], of_c[1], of_c[2], of_c[3]}), .dout(of[n]));
    end

    // ── sync ─────────────────────────────────────────────────────────────────
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(ADD_LATENCY + MUX_LATENCY + CONV_LATENCY)) u_sync_dly (
        .clk(clk), .din(tw_sync), .dout(sync_out));

endmodule
