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
// The table comes from scripts/gen_twiddle_coeffs.py: row k = w[k] =
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

    pipeline #(.BITWIDTH(2 * CW), .LATENCY(BRAM_LATENCY - 1)) u_coeff_dly (
        .clk(clk), .din(coeff_rom), .dout(coeff));

    // ── bi × w per lane ─────────────────────────────────────────────────────
    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        logic [INPUT_BIT_WIDTH-1:0] b_re_d, b_im_d;
        logic [N_BITS_PROD-1:0]     p_re, p_im;

        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(BRAM_LATENCY)) u_b_re_dly (
            .clk(clk), .din(bi_re[n]), .dout(b_re_d));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(BRAM_LATENCY)) u_b_im_dly (
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
            .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .LATENCY(CONV_LATENCY)
        ) u_conv_re (.clk(clk), .din(p_re), .dout(bwo_re[n]));

        convert #(
            .N_BITS_IN (N_BITS_PROD),         .BIN_PT_IN (BIN_PT_PROD), .TYPE_IN (1),
            .N_BITS_OUT(INPUT_BIT_WIDTH + 1), .BIN_PT_OUT(BIN_PT_IN),   .TYPE_OUT(1),
            .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .LATENCY(CONV_LATENCY)
        ) u_conv_im (.clk(clk), .din(p_im), .dout(bwo_im[n]));

        // ── a leg: delay-matched only ──────────────────────────────────────
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_re_dly (
            .clk(clk), .din(ai_re[n]), .dout(ao_re[n]));
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(LATENCY)) u_a_im_dly (
            .clk(clk), .din(ai_im[n]), .dout(ao_im[n]));
    end

    pipeline #(.BITWIDTH(1), .LATENCY(LATENCY)) u_sync_dly (
        .clk(clk), .din(sync_in), .dout(sync_out));

endmodule
