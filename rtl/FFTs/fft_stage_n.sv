// fft_stage_n — one stage of a biplex (streaming radix-2 DIF) FFT
//
// Corresponds to casper_library's fft_stage_n (fixed-point, synchronous).
// Two streams in1 / in2 enter together; a commutator pairs each sample of one
// half-frame with the sample ND = 2^(FFT_SIZE-FFT_STAGE) cycles later and
// feeds the pair to a butterfly_direct:
//
//   in1 ─► delay P ───────────► x1 ─┐           ┌─► mux1 ─► delay P+ND ─► a ┐
//   in2 ─► delay P+ND ────────► x2 ─┼─ sel ─────┤                           ├─ butterfly_direct ─► out1, out2
//                                   │           └─► mux0 ─► delay P ─────► b ┘
//   sync ─► delay P ─► counter (FFT_SIZE-FFT_STAGE+1 bits, reset) ─► sel = MSB
//        └─► delay P+MUX ─► sync_delay(ND) ─► butterfly sync
//
//   mux1 = sel ? x2 : x1,   mux0 = sel ? x1 : x2   (latency MUX_LATENCY)
//
// P = FAN_LATENCY (+ BRAM_LATENCY when the long delays are in RAM) is the
// fan-out / RAM compensation latency fft_stage_n_init.m computes; the
// equivalent single delay lines here keep the same end-to-end timing as its
// din0 / din1 / din2 / delay0 / delay1 / dmux0 / dmux1 / dsync0..2 chain.
// Long delays (P+ND) use delay_bram when DELAYS_BRAM = 1 (and ND >=
// BRAM_LATENCY, as in casper), otherwise registers.
//
// The butterfly gets casper's stage coefficients: Coeffs = [0] for stage 1,
// 0 .. 2^(FFT_STAGE-1)-1 otherwise, StepPeriod = FFT_SIZE-FFT_STAGE, biplex
// on, so stage 1 uses twiddle_pass_through, stage 2 twiddle_stage_2 and later
// stages twiddle_general, whose table INIT_FILE must hold (generate with
// rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py --fft-size FFT_SIZE --coeffs 0 .. 2^(FFT_STAGE-1)-1).
// shift[FFT_STAGE-1] is this stage's dynamic downshift; of = butterfly of |
// of_in, registered (1 cycle).
//
// LATENCY (data, sync) = 2·P + MUX_LATENCY + ND + butterfly latency.
//
// Declared for traceability only: ASYNC and FLOATING_POINT must be 0;
// FLOAT_TYPE, EXP_WIDTH, FRAC_WIDTH, ADD_PIPE_LATENCY, MULT_PIPE_LATENCY,
// COEFFS_BIT_LIMIT, COEFF_SHARING, COEFF_DECIMATION, USE_HDL, USE_EMBEDDED,
// DSP48_ADDERS and REG_RETIMING are ignored.
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
// block = 'casper_library_ffts.slx/fft_stage_n'
// deviations = [
//   "The mask's bin_pt_in = -1 backwards-compatibility value (replaced by input_bit_width-1 in fft_stage_n_init.m:147-150) is not recognised: BIN_PT_IN must be given explicitly.",
//   "OVERFLOW = 2 ('Error') has no working Simulink counterpart: butterfly_direct_init.m:512-514 compares the option against 'Flag as error', so 'Error' leaves the bus_convert overflow argument undefined and the mask init fails, whereas the HDL silently wraps (rtl/Bus/convert.sv saturates only for OVERFLOW = 1).",
//   "DSP48_ADDERS is ignored, but in Simulink dsp48_adders = 'on' forces add_latency = 2 in every butterfly_direct (butterfly_direct_init.m:194-197), so with the box ticked and ADD_LATENCY != 2 the Simulink data/sync latency differs from the HDL's.",
//   "ADD_PIPE_LATENCY / MULT_PIPE_LATENCY are ignored: in Simulink a non-zero add_pipe_latency inserts pipeline blocks on the bus_addsub inputs (bus_addsub_init.m:250-275, enabled by butterfly_direct_init.m:156-160) and mult_pipe_latency pipelines twiddle_general's bus_mult (twiddle_general_init.m:250-251), so for non-zero values the HDL has less latency (note Simulink's own fixed-point sync delay, butterfly_direct_init.m:652, does not include add_pipe_latency); only 0 is equivalent.",
//   'Bit order of of and of_in: the HDL puts lane 0 in bit 0 (of[n] = lane n), but Simulink packs the per-lane flags with bus_create/Concat, lane 0 in the MSB (butterfly_direct_init.m:625-643 munge + bus_relational -> bussify in1 = MSB, bus_relational_init.m:194); the vector is bit-reversed relative to Simulink when it has more than one bit (fft_wideband_real.sv:31-33 and its GEN_OF loop undo this for the top-level of).',
// ]
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
// note = "HDL OVERFLOW = 2 wraps (rtl/Bus/convert.sv:137 saturates only for 1), so it is exported as 'Wrap'; the mask's 'Error'/'Flag as error' option does not build or would flag instead of wrapping"
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Wrap'
//
// [params.DELAYS_BRAM]
// mask = 'delays_bram'
// type = 'checkbox'
// [params.DELAYS_BRAM.values]
// 0 = 'off'
// 1 = 'on'
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
// note = 'declared only, ignored by the HDL'
// [params.DSP48_ADDERS.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FFT_SIZE]
// mask = 'FFTSize'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [params.FFT_STAGE]
// mask = 'FFTStage'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [hdl_only]
// INIT_FILE = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// REG_RETIMING = 'fft_stage_n_init.m argument only, not a mask parameter (ignored)'
// N_BITS_OUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// note = 'each Simulink complex port x is split into x_re / x_im; the Simulink in1/in2/out1/out2 buses carry N_INPUTS complex lanes, lane 0 in the MSBs, which become array element 0'
// [ports.renamed]
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module fft_stage_n #(
    parameter int    N_INPUTS          = 1,
    parameter int    FFT_SIZE          = 5,
    parameter int    FFT_STAGE         = 5,
    parameter int    INPUT_BIT_WIDTH   = 18,
    parameter int    BIN_PT_IN         = 17,
    parameter int    COEFF_BIT_WIDTH   = 18,
    parameter int    BITGROWTH         = 0,
    parameter int    DOWNSHIFT         = 0,
    parameter int    HARDCODE_SHIFTS   = 0,
    parameter int    ADD_LATENCY       = 1,
    parameter int    MULT_LATENCY      = 2,
    parameter int    BRAM_LATENCY      = 1,
    parameter int    CONV_LATENCY      = 1,
    parameter int    QUANTIZATION      = 1,
    parameter int    OVERFLOW          = 0,
    parameter int    DELAYS_BRAM       = 1,
    parameter int    MAX_FANOUT        = 1,
    parameter string INIT_FILE         = "",
    parameter string PLATFORM          = "GENERIC",
    // declared, not implemented (see header)
    parameter int    ASYNC             = 0,
    parameter int    FLOATING_POINT    = 0,
    parameter int    FLOAT_TYPE        = 1,
    parameter int    EXP_WIDTH         = 8,
    parameter int    FRAC_WIDTH        = 24,
    parameter int    ADD_PIPE_LATENCY  = 0,
    parameter int    MULT_PIPE_LATENCY = 0,
    parameter int    COEFFS_BIT_LIMIT  = 8,
    parameter int    COEFF_SHARING     = 1,
    parameter int    COEFF_DECIMATION  = 1,
    parameter int    USE_HDL           = 0,
    parameter int    USE_EMBEDDED      = 0,
    parameter int    DSP48_ADDERS      = 0,
    parameter int    REG_RETIMING      = 1,
    // output width, derived (not meant to be overridden)
    parameter int    N_BITS_OUT        = (BITGROWTH != 0) ? INPUT_BIT_WIDTH + 1 : INPUT_BIT_WIDTH
)(
    input  logic                       clk,
    input  logic [INPUT_BIT_WIDTH-1:0] in1_re  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] in1_im  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] in2_re  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] in2_im  [N_INPUTS],
    input  logic [N_INPUTS-1:0]        of_in,
    input  logic                       sync,
    input  logic [FFT_SIZE-1:0]        shift,
    output logic [N_BITS_OUT-1:0]      out1_re [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      out1_im [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      out2_re [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      out2_im [N_INPUTS],
    output logic [N_INPUTS-1:0]        of,
    output logic                       sync_out
);

    // ⌈log2(n) / max(1, log2(mf))⌉ without floating point: the smallest k
    // with mf^k >= n (plain ⌈log2 n⌉ when mf <= 2)
    function automatic int ceil_log_ratio(int n, int mf);
        int k = 0;
        longint p = 1;
        if (mf <= 2) return $clog2(n);
        while (p < longint'(n)) begin
            p = p * longint'(mf);
            k++;
        end
        return k;
    endfunction

    localparam int ND           = 1 << (FFT_SIZE - FFT_STAGE);
    localparam int IW           = INPUT_BIT_WIDTH;
    localparam int USE_BRAM     = (DELAYS_BRAM != 0 && ND >= BRAM_LATENCY) ? 1 : 0;
    localparam int MIN_LATENCY  = (MAX_FANOUT <= 1) ? 1 : 0;
    // fft_stage_n_init.m's BRAM word-size approximation
    localparam int RIV          = FFT_SIZE - FFT_STAGE;
    localparam int WORD_SIZE    = (RIV >= 14) ? 1 : (RIV >= 13) ? 2 : (RIV >= 12) ? 4 :
                                  (RIV >= 11) ? 9 : (RIV >= 10) ? 18 : 36;
    localparam int N_BRAMS      = (N_INPUTS * IW * 2 + WORD_SIZE - 1) / WORD_SIZE;
    localparam int FAN_RAW      = (USE_BRAM != 0) ? ceil_log_ratio(N_BRAMS, MAX_FANOUT) - 1
                                                  : ceil_log_ratio(N_INPUTS, MAX_FANOUT) - 1;
    localparam int FAN_LATENCY  = (FAN_RAW > MIN_LATENCY) ? FAN_RAW : MIN_LATENCY;
    localparam int P            = FAN_LATENCY + ((USE_BRAM != 0) ? BRAM_LATENCY : 0);
    localparam int MUX_LATENCY  = (IW * N_INPUTS * 2 <= 200) ? 1 : 2;
    localparam int CNT_BITS     = FFT_SIZE - FFT_STAGE + 1;
    localparam int LANES_W      = N_INPUTS * 2 * IW;   // all lanes, re and im

    // casper stage coefficients: [0] for stage 1, 0 .. 2^(FFT_STAGE-1)-1 after
    localparam int N_COEFFS     = (FFT_STAGE == 1) ? 1 : (1 << (FFT_STAGE - 1));
    localparam int STEP_PERIOD  = FFT_SIZE - FFT_STAGE;

    if (ASYNC != 0)          $fatal(1, "fft_stage_n: ASYNC is not implemented");
    if (FLOATING_POINT != 0) $fatal(1, "fft_stage_n: FLOATING_POINT is not implemented");
    if (FFT_STAGE < 1 || FFT_STAGE > FFT_SIZE) $fatal(1, "fft_stage_n: need 1 <= FFT_STAGE <= FFT_SIZE");

    // ── pack lanes into one word (as casper's bus of n_inputs complex) ───────
    logic [LANES_W-1:0] in1_w, in2_w, x1_w, x2_w, mux1_w, mux0_w, a_w, b_w;

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_PACK
        assign in1_w[(2*n+1)*IW +: IW] = in1_re[n];
        assign in1_w[(2*n)*IW   +: IW] = in1_im[n];
        assign in2_w[(2*n+1)*IW +: IW] = in2_re[n];
        assign in2_w[(2*n)*IW   +: IW] = in2_im[n];
    end

    // ── input delays ─────────────────────────────────────────────────────────
    logic sync_d, sync_bf_pre, sync_bf;

    pipeline #(.BITWIDTH(LANES_W), .CSP_LATENCY(P)) u_x1 (.clk(clk), .din(in1_w), .dout(x1_w));
    pipeline #(.BITWIDTH(1),       .CSP_LATENCY(P)) u_sync_d (.clk(clk), .din(sync), .dout(sync_d));

    generate
        if (USE_BRAM != 0) begin : GEN_BRAM
            delay_bram #(.BITWIDTH(LANES_W), .DELAY_LEN(P + ND), .PLATFORM(PLATFORM)) u_x2 (
                .clk(clk), .din(in2_w), .dout(x2_w));
            delay_bram #(.BITWIDTH(LANES_W), .DELAY_LEN(P + ND), .PLATFORM(PLATFORM)) u_a (
                .clk(clk), .din(mux1_w), .dout(a_w));
        end else begin : GEN_REGS
            pipeline #(.BITWIDTH(LANES_W), .CSP_LATENCY(P + ND)) u_x2 (
                .clk(clk), .din(in2_w), .dout(x2_w));
            pipeline #(.BITWIDTH(LANES_W), .CSP_LATENCY(P + ND)) u_a (
                .clk(clk), .din(mux1_w), .dout(a_w));
        end
    endgenerate

    // ── commutator ───────────────────────────────────────────────────────────
    logic [CNT_BITS-1:0] cnt;

    counter #(
        .COUNTER_TYPE   (0),
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

    multiplexer #(.NBITS(LANES_W), .NINPUTS(2), .LATENCY(MUX_LATENCY)) u_mux1 (
        .clk(clk), .din('{x1_w, x2_w}), .sel(cnt[CNT_BITS-1]), .dout(mux1_w));
    multiplexer #(.NBITS(LANES_W), .NINPUTS(2), .LATENCY(MUX_LATENCY)) u_mux0 (
        .clk(clk), .din('{x2_w, x1_w}), .sel(cnt[CNT_BITS-1]), .dout(mux0_w));

    pipeline #(.BITWIDTH(LANES_W), .CSP_LATENCY(P)) u_b (.clk(clk), .din(mux0_w), .dout(b_w));

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(P + MUX_LATENCY)) u_sync_pre (
        .clk(clk), .din(sync_d), .dout(sync_bf_pre));
    sync_delay #(.DELAY_LEN(ND)) u_sync_delay (
        .clk(clk), .din(sync_bf_pre), .dout(sync_bf));

    // ── butterfly ────────────────────────────────────────────────────────────
    logic [IW-1:0]      a_re [N_INPUTS], a_im [N_INPUTS], b_re [N_INPUTS], b_im [N_INPUTS];
    logic [N_INPUTS-1:0] bf_of;

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_UNPACK
        assign a_re[n] = a_w[(2*n+1)*IW +: IW];
        assign a_im[n] = a_w[(2*n)*IW   +: IW];
        assign b_re[n] = b_w[(2*n+1)*IW +: IW];
        assign b_im[n] = b_w[(2*n)*IW   +: IW];
    end

    butterfly_direct #(
        .N_INPUTS(N_INPUTS), .BIPLEX(1), .FFT_SIZE(FFT_SIZE),
        .N_COEFFS(N_COEFFS), .COEFF_0(0), .COEFF_1(1), .STEP_PERIOD(STEP_PERIOD),
        .INIT_FILE(INIT_FILE), .COEFF_BIT_WIDTH(COEFF_BIT_WIDTH),
        .INPUT_BIT_WIDTH(IW), .BIN_PT_IN(BIN_PT_IN),
        .BITGROWTH(BITGROWTH), .DOWNSHIFT(DOWNSHIFT), .HARDCODE_SHIFTS(HARDCODE_SHIFTS),
        .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY),
        .BRAM_LATENCY(BRAM_LATENCY), .CONV_LATENCY(CONV_LATENCY),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
        .MAX_FANOUT(MAX_FANOUT), .PLATFORM(PLATFORM)
    ) u_butterfly (
        .clk(clk), .a_re(a_re), .a_im(a_im), .b_re(b_re), .b_im(b_im),
        .sync_in(sync_bf), .shift(shift[FFT_STAGE-1]),
        .apbw_re(out1_re), .apbw_im(out1_im), .ambw_re(out2_re), .ambw_im(out2_im),
        .of(bf_of), .sync_out(sync_out));

    // of = butterfly of | of_in, registered (casper logical1, latency 1)
    logical #(.NBITS(N_INPUTS), .NINPUTS(2), .LATENCY(1), .FUNC(2)) u_of_or (
        .clk(clk), .din('{bf_of, of_in}), .dout(of));

endmodule
