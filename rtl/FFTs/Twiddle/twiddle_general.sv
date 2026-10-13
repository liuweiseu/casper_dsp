// twiddle_general — general twiddle stage: bwo = bi · w[k], ao = ai (delayed)
//
// Corresponds to casper_library's twiddle_general (fixed-point, synchronous
// path). N_INPUTS complex lanes share one coefficient per cycle:
//
//   sync_in ─► counter (reset by sync) ─► addr = cnt >> STEP_PERIOD
//                                          │
//                                          ▼
//                  rom (INIT_FILE, {re,im}) ─► pipeline(BRAM_LATENCY-1) ─► w
//   bi ─► pipeline(BRAM_LATENCY) ────────────────────────────────────────► ×w
//        ─► complex_multiplier (exact) ─► convert (QUANTIZATION, OVERFLOW) ─► bwo
//   ai, sync_in ─► pipeline(LATENCY) ─► ao, sync_out
//
// Coefficient schedule: the counter is cleared by sync_in, so the sample
// arriving the cycle after a sync pulse (CASPER's first sample of a frame) is
// multiplied by w[0]; each table row is used for 2^STEP_PERIOD consecutive
// cycles, then the next row, wrapping after N_COEFFS rows (N_COEFFS need not
// be a power of two). Without sync pulses the counter free-runs from 0.
//
// The table comes from rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py: row k = w[k] =
// exp(-2πj · bit_rev(Coeffs[k], FFT_SIZE-1) / 2^FFT_SIZE), each part a
// COEFF_BIT_WIDTH-bit signed word with binary point COEFF_BIT_WIDTH-1,
// packed {re, im} (re in the upper half).
//
// Formats (as casper_library's twiddle_general):
//   ai, bi, ao    : INPUT_BIT_WIDTH bits, binary point BIN_PT_IN, signed
//   bwo           : INPUT_BIT_WIDTH+1 bits, binary point BIN_PT_IN, signed
//                   (one bit of growth: |b·w| can exceed |b| components)
//   multiplier    : exact, INPUT_BIT_WIDTH+COEFF_BIT_WIDTH+1 bits
//   QUANTIZATION / OVERFLOW apply in the final convert (encodings as in
//   rtl/Bus/convert: 0=truncate, 1=round ±inf, 2=round even / 0=wrap,
//   1=saturate).
//
// Latency of every output: LATENCY = BRAM_LATENCY + MULT_LATENCY +
// ADD_LATENCY + CONV_LATENCY. With BRAM_LATENCY = 1 this equals the
// 1+mult_latency+add_latency+conv_latency of twiddle_coeff_0 / twiddle_coeff_1,
// so butterfly_direct can swap the variants without re-timing.
//
// ASYNC = 1 (casper async): en enables the coefficient address counter, so
// the coefficients step over valid samples only; dvalid = en delayed LATENCY.
//
// Declared for parameter traceability only (casper_library options not
// implemented in v1): FLOATING_POINT must be 0; FLOAT_TYPE,
// EXP_WIDTH, FRAC_WIDTH, COEFF_SHARING, COEFF_DECIMATION, COEFF_GENERATION,
// CAL_BITS, N_BITS_ROTATION, MAX_FANOUT, USE_HDL, USE_EMBEDDED and
// COEFFS_BIT_LIMIT are ignored. FFT_SIZE documents the table's FFT size; the
// table itself is fixed by INIT_FILE and N_COEFFS.
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
// block = 'casper_library_ffts_twiddle.slx/twiddle_general'
// deviations = [
//   "latency differs from Simulink: the HDL has LATENCY = BRAM_LATENCY+MULT_LATENCY+ADD_LATENCY+CONV_LATENCY on ao/bwo/sync_out, but casper routes ai/bi/sync through coeff_gen's misc path (twiddle_general_init.m:180-183) so in the common cosin case (in-order Coeffs, or coeff_generation off) they gain the cosin latency bram+add+conv+2 (cosin_init.m:917 mux+add+conv with mux_latency 1, :240 bram, :1018 mux+neg with neg_latency 0; coeff_gen_init.m:452), then bus_mult mult+add (fan_latency 0) and bus_convert conv: bram+mult+2*add+2*conv+2 in total, add+conv+2 cycles more than the HDL (derived from the init scripts, not simulated)",
//   'with a single coefficient Simulink uses two Constants (no ROM, no latency) quantized to coeff_bit_width-2 fractional bits (coeff_gen_init.m:156-157) giving mult+add+conv latency; the HDL always uses the ROM (COEFF_BIT_WIDTH-1 fractional bits) and BRAM_LATENCY (>= 1) more cycles',
//   "for bit-reversed Coeffs with coeff_generation='on' and log2(length(Coeffs)) > ceil(log2(mult+add+conv+1))+cal_bits, Simulink generates coefficients with feedback_osc (recursive rotation at n_bits_rotation precision, different latency; coeff_gen_init.m:534) - values and timing then differ from the HDL's flat ROM; COEFF_GENERATION/CAL_BITS/N_BITS_ROTATION are ignored",
//   "coefficient words: the HDL table (gen_twiddle_coeffs.py) rounds half away from zero and saturates each w[k] directly; cosin stores a partial cycle and derives the rest by negation/swap (Negate 'Saturate', cosin_init.m invert_init), so values at |w| = 1 (e.g. -1.0 = -(saturated +1)) may differ by 1 LSB (unverified)",
//   'the HDL accepts any N_COEFFS (also non-powers of two, arbitrary order); coeff_gen_init.m:282-290 errors unless the FFT size is a power-of-two multiple of length(Coeffs) and Coeffs are in order or bit-reversed',
//   "the address counter is cleared by sync_in in both models (coeff_gen Counter rst='on'); the HDL requires BRAM_LATENCY >= 1 ($fatal), Simulink accepts 0",
//   'add_pipe_latency / mult_pipe_latency (bus_mult pipeline_cmult_en) and max_fanout / use_hdl / use_embedded (multiplier implementation) are not modelled',
//   'test vectors in casper_dsp/test_data/FFTs/Twiddle/twiddle_general/test_data.md come from a Python reference model (not exported from MATLAB), so cycle/bit equivalence with the Simulink block is unverified',
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
// note = "HDL OVERFLOW = 2 wraps (rtl/Bus/convert.sv:137 saturates only for 1), so it is exported as 'Wrap'; the mask's 'Error'/'Flag as error' option does not build or would flag instead of wrapping"
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Wrap'
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// note = 'async = on: en enables the coefficient address counter (sync still clears it); dvalid = en delayed with ai / sync_out; the data path is not gated. The HDL ports always exist, dvalid = 0 when ASYNC = 0'
// [params.ASYNC.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FLOATING_POINT]
// mask = 'floating_point'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = 'floating point is not implemented: elaboration stops with $fatal'
// [params.FLOATING_POINT.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FLOAT_TYPE]
// mask = 'float_type'
// type = 'popup'
// note = 'mask radiobutton; declared only, ignored by the HDL'
// [params.FLOAT_TYPE.values]
// 1 = 'single'
// 2 = 'custom'
//
// [params.COEFF_SHARING]
// mask = 'coeff_sharing'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL (flat coefficient ROM)'
// [params.COEFF_SHARING.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.COEFF_DECIMATION]
// mask = 'coeff_decimation'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL (flat coefficient ROM)'
// [params.COEFF_DECIMATION.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.COEFF_GENERATION]
// mask = 'coeff_generation'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL (flat coefficient ROM)'
// [params.COEFF_GENERATION.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_HDL]
// mask = 'use_hdl'
// type = 'checkbox'
// note = 'declared only, ignored by the HDL (flat coefficient ROM)'
// [params.USE_HDL.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_EMBEDDED]
// mask = 'use_embedded'
// type = 'checkbox'
// note = "declared only, ignored by the HDL (flat coefficient ROM); HDL default 0 differs from the mask default 'on'"
// [params.USE_EMBEDDED.values]
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
// [mask_set.Coeffs]
// from_params_json = 'COEFFS'
// [mask_set.Coeffs.else]
// manual = "coefficient index vector, length N_COEFFS: the coeffs list INIT_FILE was generated from (rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py --coeffs). INIT_FILE holds only the quantized values w[k] = exp(-2*pi*j*bit_rev(Coeffs[k], FFT_SIZE-1)/2^FFT_SIZE), so Coeffs[k] = bit_rev(round(-angle(w[k])*2^FFT_SIZE/(2*pi)) mod 2^FFT_SIZE, FFT_SIZE-1), which recovers indices below 2^(FFT_SIZE-1) only (bit_rev drops higher bits); from_mem cannot express this decode"
//
// [[unsupported]]
// when = 'N_COEFFS > 1 && 2 ** $clog2(N_COEFFS) != N_COEFFS'
// reason = 'coeff_gen_init.m:281-285 errors (The FFT size must be a power-of-two-multiple of the number of coefficients) when 2^(FFTSize-StepPeriod) / (Coeffs(end) + step - Coeffs(1)) is not a power of two; for an in-order or bit-reversed list with a constant step this span is N_COEFFS * step, so N_COEFFS must be a power of two. A length-3 list is also always treated as in order (coeff_gen_init.m:209-213 checks no step) and errors at coeff_gen_init.m:267-271 unless Coeffs(1) = 0. From source, not run in MATLAB'
//
// [[unsupported]]
// when = 'N_COEFFS > 1 && FFT_SIZE - STEP_PERIOD < 3'
// reason = 'mlib_devel bug 6 (docs/bugs.md): for in-order Coeffs 0, 1, ..., N_COEFFS-1, coeff_gen gives cosin full_cycle_bits = FFT_SIZE - STEP_PERIOD; below 3, draw_basic_partial_cycle (cosin_init.m:660-663) draws no add_convert1 but cosin_init.m:226 connects to it: Invalid Simulink object name: add_convert1/2 (confirmed in MATLAB R2021a, set 1). The rule depends on the Coeffs list, which the HDL only has in INIT_FILE; this when assumes in-order coefficients'
//
// [hdl_only]
// N_COEFFS = "length(Coeffs): replaces the mask's vector Coeffs"
// INIT_FILE = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// add_pipe_latency = 'not implemented'
// mult_pipe_latency = 'not implemented'
//
// [ports]
// order = 'Simulink: ai, bi, sync_in, en (async only) -> ao, bwo, sync_out, dvalid (async only) (checked on a built block); HDL: the same order with ai / bi / ao / bwo split into re / im lanes'
// note = 'each Simulink complex port x is split into x_re / x_im'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module twiddle_general #(
    parameter int    N_INPUTS         = 1,
    parameter int    FFT_SIZE         = 2,
    parameter int    N_COEFFS         = 2,
    parameter int    STEP_PERIOD      = 0,
    parameter int    INPUT_BIT_WIDTH  = 18,
    parameter int    BIN_PT_IN        = 17,
    parameter int    COEFF_BIT_WIDTH  = 18,
    parameter int    MULT_LATENCY     = 2,
    parameter int    ADD_LATENCY      = 1,
    parameter int    CONV_LATENCY     = 1,
    parameter int    BRAM_LATENCY     = 1,
    parameter int    QUANTIZATION     = 1,
    parameter int    OVERFLOW         = 0,
    parameter string INIT_FILE        = "",
    parameter string PLATFORM         = "GENERIC",
    parameter int    ASYNC            = 0,    // casper async: 1 = en / dvalid
    // declared, not implemented (see header)
    parameter int    FLOATING_POINT   = 0,
    parameter int    FLOAT_TYPE       = 1,
    parameter int    EXP_WIDTH        = 8,
    parameter int    FRAC_WIDTH       = 24,
    parameter int    COEFF_SHARING    = 1,
    parameter int    COEFF_DECIMATION = 1,
    parameter int    COEFF_GENERATION = 1,
    parameter int    CAL_BITS         = 1,
    parameter int    N_BITS_ROTATION  = 25,
    parameter int    MAX_FANOUT       = 4,
    parameter int    USE_HDL          = 0,
    parameter int    USE_EMBEDDED     = 0,
    parameter int    COEFFS_BIT_LIMIT = 9
)(
    input  logic                       clk,
    input  logic [INPUT_BIT_WIDTH-1:0] ai_re  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] ai_im  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] bi_re  [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] bi_im  [N_INPUTS],
    input  logic                       sync_in,
    input  logic                       en = 1'b1,
    output logic [INPUT_BIT_WIDTH-1:0] ao_re  [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] ao_im  [N_INPUTS],
    output logic [INPUT_BIT_WIDTH:0]   bwo_re [N_INPUTS],
    output logic [INPUT_BIT_WIDTH:0]   bwo_im [N_INPUTS],
    output logic                       sync_out,
    output logic                       dvalid
);

    localparam int LATENCY     = BRAM_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY;
    localparam int PERIOD      = N_COEFFS << STEP_PERIOD;     // counter period
    localparam int CNT_BITS    = (PERIOD > 1) ? $clog2(PERIOD) : 1;
    localparam int ADDR_WIDTH  = (N_COEFFS > 1) ? $clog2(N_COEFFS) : 1;
    localparam int CW          = COEFF_BIT_WIDTH;
    localparam int N_BITS_PROD = INPUT_BIT_WIDTH + COEFF_BIT_WIDTH + 1;
    localparam int BIN_PT_PROD = BIN_PT_IN + COEFF_BIT_WIDTH - 1;

    if (FLOATING_POINT != 0) $fatal(1, "twiddle_general: FLOATING_POINT is not implemented");
    if (BRAM_LATENCY < 1)    $fatal(1, "twiddle_general: BRAM_LATENCY must be >= 1 (rom read latency)");

    // ── coefficient address: counter cleared by sync_in ─────────────────────
    // ASYNC = 1: the counter only advances on en = 1 (coeff_gen Counter en,
    // coeff_gen_init.m:408-416); sync still clears it (rst wins over en)
    logic [CNT_BITS-1:0]   cnt;
    logic [ADDR_WIDTH-1:0] addr;

    counter #(
        .COUNTER_TYPE   (1),              // count_limit: 0 .. PERIOD-1
        .NBITS          (CNT_BITS),
        .COUNT_TO_VAL   (PERIOD - 1),
        .COUNT_DIR      (0),
        .INIT_VAL       (0),
        .STEP           (1),
        .ENABLE_SYNC_RST(1),
        .ENABLE_ENABLE  (int'(ASYNC != 0))
    ) u_counter (
        .clk   (clk),
        .rst   (sync_in),
        .enable(en),
        .dout  (cnt)
    );

    assign addr = ADDR_WIDTH'(cnt >> STEP_PERIOD);

    // ── coefficient table ───────────────────────────────────────────────────
    logic [2*CW-1:0] coeff_rom, coeff;

    rom #(
        .DATA_WIDTH(2 * CW),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE (INIT_FILE),
        .PLATFORM  (PLATFORM)
    ) u_rom (
        .clk (clk),
        .addr(addr),
        .dout(coeff_rom)
    );

    pipeline #(.BITWIDTH(2 * CW), .CSP_LATENCY(BRAM_LATENCY - 1)) u_coeff_dly (
        .clk(clk), .din(coeff_rom), .dout(coeff));

    // ── bi × w per lane ─────────────────────────────────────────────────────
    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        logic [INPUT_BIT_WIDTH-1:0] b_re_d, b_im_d;
        logic [N_BITS_PROD-1:0]     p_re, p_im;

        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(BRAM_LATENCY)) u_b_re_dly (
            .clk(clk), .din(bi_re[n]), .dout(b_re_d));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(BRAM_LATENCY)) u_b_im_dly (
            .clk(clk), .din(bi_im[n]), .dout(b_im_d));

        // exact product (quantization 0 / overflow 0 cannot lose anything
        // at this width), as bus_mult in casper_library's twiddle_general
        complex_multiplier #(
            .N_BITS_A    (INPUT_BIT_WIDTH), .BIN_PT_A(BIN_PT_IN), .TYPE_A(1),
            .N_BITS_B    (CW),              .BIN_PT_B(CW - 1),    .TYPE_B(1),
            .N_BITS_OUT  (N_BITS_PROD),     .BIN_PT_OUT(BIN_PT_PROD), .TYPE_OUT(1),
            .QUANTIZATION(0), .OVERFLOW(0),
            .MULT_SPEC   (0),
            .MULT_LATENCY(MULT_LATENCY),
            .ADD_LATENCY (ADD_LATENCY)
        ) u_cmult (
            .clk    (clk),
            .a_re   (b_re_d),
            .a_im   (b_im_d),
            .b_re   (coeff[2*CW-1:CW]),
            .b_im   (coeff[CW-1:0]),
            .dout_re(p_re),
            .dout_im(p_im),
            .dout_tvalid()
        );

        convert #(
            .N_BITS_IN (N_BITS_PROD),         .BIN_PT_IN (BIN_PT_PROD), .TYPE_IN (1),
            .N_BITS_OUT(INPUT_BIT_WIDTH + 1), .BIN_PT_OUT(BIN_PT_IN),   .TYPE_OUT(1),
            .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CONV_LATENCY)
        ) u_conv_re (.clk(clk), .din(p_re), .dout(bwo_re[n]), .overflow(), .misco());

        convert #(
            .N_BITS_IN (N_BITS_PROD),         .BIN_PT_IN (BIN_PT_PROD), .TYPE_IN (1),
            .N_BITS_OUT(INPUT_BIT_WIDTH + 1), .BIN_PT_OUT(BIN_PT_IN),   .TYPE_OUT(1),
            .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CONV_LATENCY)
        ) u_conv_im (.clk(clk), .din(p_im), .dout(bwo_im[n]), .overflow(), .misco());

        // ── a leg: delay-matched only ──────────────────────────────────────
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_a_re_dly (
            .clk(clk), .din(ai_re[n]), .dout(ao_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_a_im_dly (
            .clk(clk), .din(ai_im[n]), .dout(ao_im[n]));
    end

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(LATENCY)) u_sync_dly (
        .clk(clk), .din(sync_in), .dout(sync_out));

    // ASYNC = 1: dvalid = en, carried with sync / ai (casper: the en bit of the
    // coeff_gen misc bus, twiddle_general_init.m:146-205); 0 when ASYNC = 0
    if (ASYNC != 0) begin : GEN_DVALID
        pipeline #(.BITWIDTH(1), .CSP_LATENCY(LATENCY)) u_dvalid (
            .clk(clk), .din(en), .dout(dvalid));
    end else begin : GEN_NO_DVALID
        assign dvalid = 1'b0;
    end

endmodule
