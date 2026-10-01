// fft_wideband_real — 2^FFT_SIZE-point real FFT, 2^N_INPUTS samples per cycle
//
// Corresponds to casper_library's fft_wideband_real (fixed point, sync mode,
// fft_wideband_real_init.m). Each of the N_STREAMS streams presents
// 2^N_INPUTS real samples per cycle (in<s><n>); the outputs are the
// 2^(N_INPUTS-1) complex bins per cycle of the lower half of the spectrum
// (out<s><n>). As fft_wideband_real_init.m wires it (F = FFT_SIZE,
// NI = N_INPUTS, NS = N_STREAMS):
//
//   in<s><n> ─► pipeline INPUT_LATENCY ─► fft_biplex_real_4x pol<s·2^NI+n>_in
//      fft_biplex_real_4x: N_BIPLEX_INPUTS = NS·2^(NI-2), FFT_SIZE = F-NI
//      (the first F-NI stages), shift = shift (only its low F-NI bits are used)
//   pol<s·2^NI+n>_out ─► pipeline BIPLEX_DIRECT_LATENCY ─► fft_direct in<s><n>
//      fft_direct: N_STREAMS = NS, FFT_SIZE = NI (the last NI stages),
//      MAP_TAIL on, LARGER_FFT_SIZE = F, START_STAGE = F-NI+1,
//      shift = shift[F-1 : F-NI]
//   fft_direct out<s><n>, n < 2^(NI-1) (the upper half is terminated):
//      UNSCRAMBLE: ─► pipeline BIPLEX_DIRECT_LATENCY ─► fft_unscrambler
//                  (FFT_SIZE = F-1, LOG2_N_GROUPS = NI-1, N_STREAMS = NS)
//                  in<s><n> ─► out<s><n>; sync likewise
//      otherwise : ─► out<s><n> directly; sync_out = fft_direct's sync_out
//   of = fft_direct of | fft_biplex_real_4x of (Logical OR, latency 1)
//
// As in casper, UNSCRAMBLE is treated as off when N_INPUTS = 1, and
// 2^N_INPUTS·N_STREAMS must be a multiple of 4. With HARDCODE_SHIFTS,
// SHIFT_SCHEDULE (bit k = stage k+1) is split: the low F-NI bits go to the
// biplex part, the rest to fft_direct. Widths: fft_direct gets
// BITGROWTH ? min(MAX_BITS, IW+F-NI) : IW bits, the outputs are
// BITGROWTH ? min(MAX_BITS, IW+F) : IW bits (binary point BIN_PT_IN).
//
// of: casper's OR aligns its inputs at the LSB: fft_biplex_real_4x's of has
// N_BIPLEX_INPUTS bits (lane 0 = MSB), fft_direct's N_STREAMS bits (stream
// 0 = MSB), so of has max of the two widths, bit b = biplex lane
// N_BIPLEX_INPUTS-1-b | fft_direct stream N_STREAMS-1-b (missing bits 0).
//
// Memory files, all in MEM_DIR (rtl/FFTs/scripts/gen_fft_mem_files.py
// wideband_real writes them): twiddle_stage<s>.mem (biplex_core),
// map_even.mem / map_odd.mem / map_out.mem (bi_real_unscr_4x),
// twiddle_direct_s<s>_<u>.mem (fft_direct), map_unscrambler.mem
// (fft_unscrambler).
//
// Port order: element k of din is in<s><n> with k = s·2^NI + n, element k of
// dout is out<s><n> with k = s·2^(NI-1) + n (casper port order).
//
// Declared for traceability only: ASYNC and FLOATING_POINT must be 0;
// FLOAT_TYPE, EXP_WIDTH, FRAC_WIDTH, ADD_PIPE_LATENCY, MULT_PIPE_LATENCY,
// COEFF_SHARING, COEFF_DECIMATION, COEFF_GENERATION, CAL_BITS,
// N_BITS_ROTATION, MULT_SPEC and DSP48_ADDERS are ignored.

module fft_wideband_real #(
    parameter int    N_STREAMS             = 1,
    parameter int    FFT_SIZE              = 6,
    parameter int    N_INPUTS              = 2,
    parameter int    INPUT_BIT_WIDTH       = 18,
    parameter int    BIN_PT_IN             = 17,
    parameter int    COEFF_BIT_WIDTH       = 18,
    parameter int    UNSCRAMBLE            = 1,
    parameter int    ADD_LATENCY           = 1,
    parameter int    MULT_LATENCY          = 2,
    parameter int    BRAM_LATENCY          = 2,
    parameter int    CONV_LATENCY          = 0,
    parameter int    INPUT_LATENCY         = 0,
    parameter int    BIPLEX_DIRECT_LATENCY = 0,
    parameter int    QUANTIZATION          = 1,
    parameter int    OVERFLOW              = 1,
    parameter int    DELAYS_BIT_LIMIT      = 8,
    parameter int    COEFFS_BIT_LIMIT      = 8,
    parameter int    MAX_FANOUT            = 4,
    parameter int    BITGROWTH             = 0,
    parameter int    MAX_BITS              = 19,
    parameter int    HARDCODE_SHIFTS       = 0,
    parameter int    SHIFT_SCHEDULE        = 31,
    parameter string MEM_DIR               = "",
    parameter string PLATFORM              = "GENERIC",
    // declared, not implemented (see header)
    parameter int    ASYNC                 = 0,
    parameter int    FLOATING_POINT        = 0,
    parameter int    FLOAT_TYPE            = 1,
    parameter int    EXP_WIDTH             = 8,
    parameter int    FRAC_WIDTH            = 24,
    parameter int    ADD_PIPE_LATENCY      = 0,
    parameter int    MULT_PIPE_LATENCY     = 0,
    parameter int    COEFF_SHARING         = 1,
    parameter int    COEFF_DECIMATION      = 1,
    parameter int    COEFF_GENERATION      = 1,
    parameter int    CAL_BITS              = 1,
    parameter int    N_BITS_ROTATION       = 25,
    parameter int    MULT_SPEC             = 2,
    parameter int    DSP48_ADDERS          = 0,
    // derived (not meant to be overridden)
    parameter int    N_BITS_OUT            = (BITGROWTH != 0) ? ((INPUT_BIT_WIDTH + FFT_SIZE < MAX_BITS)
                                             ? INPUT_BIT_WIDTH + FFT_SIZE : MAX_BITS) : INPUT_BIT_WIDTH,
    parameter int    OF_WIDTH              = ((N_STREAMS << N_INPUTS) / 4 > N_STREAMS)
                                             ? (N_STREAMS << N_INPUTS) / 4 : N_STREAMS
)(
    input  logic                       clk,
    input  logic                       sync,
    input  logic [FFT_SIZE-1:0]        shift,
    input  logic [INPUT_BIT_WIDTH-1:0] din     [N_STREAMS << N_INPUTS],
    output logic                       sync_out,
    output logic [N_BITS_OUT-1:0]      dout_re [N_STREAMS << (N_INPUTS - 1)],
    output logic [N_BITS_OUT-1:0]      dout_im [N_STREAMS << (N_INPUTS - 1)],
    output logic [OF_WIDTH-1:0]        of
);

    localparam int F      = FFT_SIZE;
    localparam int NI     = N_INPUTS;
    localparam int NS     = N_STREAMS;
    localparam int FB     = F - NI;                      // biplex stages
    localparam int NB     = (NS << NI) / 4;              // N_BIPLEX_INPUTS
    localparam int NIN    = NS << NI;                    // real inputs
    localparam int NOUT   = NS << (NI - 1);              // complex outputs
    localparam int UNSCR  = (UNSCRAMBLE != 0 && NI != 1) ? 1 : 0;
    localparam int W_DIR  = (BITGROWTH != 0) ? ((INPUT_BIT_WIDTH + FB < MAX_BITS)
                            ? INPUT_BIT_WIDTH + FB : MAX_BITS) : INPUT_BIT_WIDTH;

    if (ASYNC != 0)          $fatal(1, "fft_wideband_real: ASYNC is not implemented");
    if (FLOATING_POINT != 0) $fatal(1, "fft_wideband_real: FLOATING_POINT is not implemented");
    if (NI < 1)              $fatal(1, "fft_wideband_real: N_INPUTS must be >= 1");
    if ((NIN % 4) != 0)
        $fatal(1, "fft_wideband_real: 2^N_INPUTS * N_STREAMS must be a multiple of 4");
    if (FB < 2)              $fatal(1, "fft_wideband_real: FFT_SIZE - N_INPUTS must be >= 2 (biplex_core)");

    // ── input pipelines ─────────────────────────────────────────────────────
    logic [INPUT_BIT_WIDTH-1:0] din_d [NIN];
    logic                       sync_d;

    pipeline #(.BITWIDTH(1), .LATENCY(INPUT_LATENCY)) u_in_del_sync_4x (
        .clk(clk), .din(sync), .dout(sync_d));
    for (genvar k = 0; k < NIN; k++) begin : GEN_IN_DEL
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .LATENCY(INPUT_LATENCY)) u_in_del_4x_pol (
            .clk(clk), .din(din[k]), .dout(din_d[k]));
    end

    // ── first F-NI stages: fft_biplex_real_4x ────────────────────────────────
    logic [W_DIR-1:0] bx_re [NIN], bx_im [NIN], bxd_re [NIN], bxd_im [NIN];
    logic [NB-1:0]    bx_of;
    logic             bx_sync, bxd_sync;

    fft_biplex_real_4x #(
        .N_BIPLEX_INPUTS(NB), .FFT_SIZE(FB), .INPUT_BIT_WIDTH(INPUT_BIT_WIDTH),
        .BIN_PT_IN(BIN_PT_IN), .COEFF_BIT_WIDTH(COEFF_BIT_WIDTH),
        .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY), .BRAM_LATENCY(BRAM_LATENCY),
        .CONV_LATENCY(CONV_LATENCY), .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
        .DELAYS_BIT_LIMIT(DELAYS_BIT_LIMIT), .COEFFS_BIT_LIMIT(COEFFS_BIT_LIMIT),
        .MAX_FANOUT(MAX_FANOUT), .BITGROWTH(BITGROWTH), .MAX_BITS(MAX_BITS),
        .HARDCODE_SHIFTS(HARDCODE_SHIFTS), .SHIFT_SCHEDULE(SHIFT_SCHEDULE & ((1 << FB) - 1)),
        .COEFF_DIR(MEM_DIR), .MAP_DIR(MEM_DIR), .PLATFORM(PLATFORM)
    ) u_fft_biplex_real_4x (
        .clk(clk), .sync(sync_d), .shift(shift[FB-1:0]), .pol_in(din_d),
        .sync_out(bx_sync), .pol_out_re(bx_re), .pol_out_im(bx_im), .of(bx_of));

    pipeline #(.BITWIDTH(1), .LATENCY(BIPLEX_DIRECT_LATENCY)) u_del_sync_4x (
        .clk(clk), .din(bx_sync), .dout(bxd_sync));
    for (genvar k = 0; k < NIN; k++) begin : GEN_BX_DEL
        pipeline #(.BITWIDTH(2 * W_DIR), .LATENCY(BIPLEX_DIRECT_LATENCY)) u_del_4x_pol (
            .clk(clk), .din({bx_im[k], bx_re[k]}), .dout({bxd_im[k], bxd_re[k]}));
    end

    // ── last NI stages: fft_direct ───────────────────────────────────────────
    logic [N_BITS_OUT-1:0] fd_re [NIN], fd_im [NIN];
    logic [NS-1:0]         fd_of;
    logic                  fd_sync;

    fft_direct #(
        .N_STREAMS(NS), .FFT_SIZE(NI), .INPUT_BIT_WIDTH(W_DIR), .BIN_PT_IN(BIN_PT_IN),
        .COEFF_BIT_WIDTH(COEFF_BIT_WIDTH), .MAP_TAIL(1), .LARGER_FFT_SIZE(F), .START_STAGE(FB + 1),
        .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY), .BRAM_LATENCY(BRAM_LATENCY),
        .CONV_LATENCY(CONV_LATENCY), .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
        .MAX_FANOUT(MAX_FANOUT), .BITGROWTH(BITGROWTH), .MAX_BITS(MAX_BITS),
        .HARDCODE_SHIFTS(HARDCODE_SHIFTS), .SHIFT_SCHEDULE(SHIFT_SCHEDULE >> FB),
        .COEFFS_BIT_LIMIT(COEFFS_BIT_LIMIT), .COEFF_DIR(MEM_DIR), .PLATFORM(PLATFORM)
    ) u_fft_direct (
        .clk(clk), .sync(bxd_sync), .shift(shift[F-1:FB]), .din_re(bxd_re), .din_im(bxd_im),
        .sync_out(fd_sync), .dout_re(fd_re), .dout_im(fd_im), .of(fd_of));

    // lower half of each stream's outputs (casper terminates the upper half)
    logic [N_BITS_OUT-1:0] kept_re [NOUT], kept_im [NOUT];
    for (genvar st = 0; st < NS; st++) begin : GEN_KEEP_S
        for (genvar n = 0; n < (1 << (NI - 1)); n++) begin : GEN_KEEP_N
            assign kept_re[st * (1 << (NI - 1)) + n] = fd_re[st * (1 << NI) + n];
            assign kept_im[st * (1 << (NI - 1)) + n] = fd_im[st * (1 << NI) + n];
        end
    end

    // ── optional unscrambler ─────────────────────────────────────────────────
    if (UNSCR != 0) begin : GEN_UNSCRAMBLE
        logic [N_BITS_OUT-1:0] kd_re [NOUT], kd_im [NOUT];
        logic                  fd_sync_d;

        pipeline #(.BITWIDTH(1), .LATENCY(BIPLEX_DIRECT_LATENCY)) u_fft_direct_sync_delay (
            .clk(clk), .din(fd_sync), .dout(fd_sync_d));
        for (genvar k = 0; k < NOUT; k++) begin : GEN_DEL_DIRECT
            pipeline #(.BITWIDTH(2 * N_BITS_OUT), .LATENCY(BIPLEX_DIRECT_LATENCY)) u_del_direct (
                .clk(clk), .din({kept_im[k], kept_re[k]}), .dout({kd_im[k], kd_re[k]}));
        end

        fft_unscrambler #(
            .N_STREAMS(NS), .FFT_SIZE(F - 1), .LOG2_N_GROUPS(NI - 1), .N_BITS_IN(N_BITS_OUT),
            .BRAM_LATENCY(BRAM_LATENCY), .COEFFS_BIT_LIMIT(COEFFS_BIT_LIMIT),
            .MAP_INIT_FILE({MEM_DIR, "map_unscrambler.mem"}), .PLATFORM(PLATFORM)
        ) u_fft_unscrambler (
            .clk(clk), .sync(fd_sync_d), .din_re(kd_re), .din_im(kd_im),
            .sync_out(sync_out), .dout_re(dout_re), .dout_im(dout_im));
    end else begin : GEN_DIRECT_OUT
        assign sync_out = fd_sync;
        assign dout_re  = kept_re;
        assign dout_im  = kept_im;
    end

    // ── overflow: LSB-aligned OR of the two blocks' of, latency 1 ───────────
    logic [OF_WIDTH-1:0] of_a, of_b;
    for (genvar b = 0; b < OF_WIDTH; b++) begin : GEN_OF
        assign of_a[b] = (b < NS) ? fd_of[(b < NS) ? NS - 1 - b : 0] : 1'b0;
        assign of_b[b] = (b < NB) ? bx_of[(b < NB) ? NB - 1 - b : 0] : 1'b0;
    end
    logical #(.NBITS(OF_WIDTH), .NINPUTS(2), .LATENCY(1), .FUNC(2)) u_of_or (
        .clk(clk), .din('{of_a, of_b}), .dout(of));

endmodule
