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
// Declared for parameter traceability only (casper_library options not
// implemented in v1): ASYNC and FLOATING_POINT must be 0; FLOAT_TYPE,
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
// hdl_unsupported = [2]
// note = "the mask option is 'Error' but twiddle_general_init.m:117/324 only recognise 'Flag as error', so selecting it leaves 'of' undefined and the Simulink mask init fails; the HDL treats 2 as wrap"
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Error'
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = 'async=on (en/dvalid ports) is not implemented: elaboration stops with $fatal'
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
// [hdl_only]
// N_COEFFS = "length(Coeffs): replaces the mask's vector Coeffs"
// INIT_FILE = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// Coeffs = 'vector parameter: replaced by N_COEFFS and the coefficient file'
// add_pipe_latency = 'not implemented'
// mult_pipe_latency = 'not implemented'
//
// [ports]
// note = 'each Simulink complex port x is split into x_re / x_im'
// [ports.renamed]
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
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
    // declared, not implemented (see header)
    parameter int    ASYNC            = 0,
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
    output logic [INPUT_BIT_WIDTH-1:0] ao_re  [N_INPUTS],
    output logic [INPUT_BIT_WIDTH-1:0] ao_im  [N_INPUTS],
    output logic [INPUT_BIT_WIDTH:0]   bwo_re [N_INPUTS],
    output logic [INPUT_BIT_WIDTH:0]   bwo_im [N_INPUTS],
    output logic                       sync_out
);

    localparam int LATENCY     = BRAM_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY;
    localparam int PERIOD      = N_COEFFS << STEP_PERIOD;     // counter period
    localparam int CNT_BITS    = (PERIOD > 1) ? $clog2(PERIOD) : 1;
    localparam int ADDR_WIDTH  = (N_COEFFS > 1) ? $clog2(N_COEFFS) : 1;
    localparam int CW          = COEFF_BIT_WIDTH;
    localparam int N_BITS_PROD = INPUT_BIT_WIDTH + COEFF_BIT_WIDTH + 1;
    localparam int BIN_PT_PROD = BIN_PT_IN + COEFF_BIT_WIDTH - 1;

    if (ASYNC != 0)          $fatal(1, "twiddle_general: ASYNC is not implemented");
    if (FLOATING_POINT != 0) $fatal(1, "twiddle_general: FLOATING_POINT is not implemented");
    if (BRAM_LATENCY < 1)    $fatal(1, "twiddle_general: BRAM_LATENCY must be >= 1 (rom read latency)");

    // ── coefficient address: counter cleared by sync_in ─────────────────────
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
        .ENABLE_ENABLE  (0)
    ) u_counter (
        .clk   (clk),
        .rst   (sync_in),
        .enable(1'b1),
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
            .dout_im(p_im)
        );

        convert #(
            .N_BITS_IN (N_BITS_PROD),         .BIN_PT_IN (BIN_PT_PROD), .TYPE_IN (1),
            .N_BITS_OUT(INPUT_BIT_WIDTH + 1), .BIN_PT_OUT(BIN_PT_IN),   .TYPE_OUT(1),
            .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CONV_LATENCY)
        ) u_conv_re (.clk(clk), .din(p_re), .dout(bwo_re[n]));

        convert #(
            .N_BITS_IN (N_BITS_PROD),         .BIN_PT_IN (BIN_PT_PROD), .TYPE_IN (1),
            .N_BITS_OUT(INPUT_BIT_WIDTH + 1), .BIN_PT_OUT(BIN_PT_IN),   .TYPE_OUT(1),
            .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(CONV_LATENCY)
        ) u_conv_im (.clk(clk), .din(p_im), .dout(bwo_im[n]));

        // ── a leg: delay-matched only ──────────────────────────────────────
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_a_re_dly (
            .clk(clk), .din(ai_re[n]), .dout(ao_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(LATENCY)) u_a_im_dly (
            .clk(clk), .din(ai_im[n]), .dout(ao_im[n]));
    end

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(LATENCY)) u_sync_dly (
        .clk(clk), .din(sync_in), .dout(sync_out));

endmodule
