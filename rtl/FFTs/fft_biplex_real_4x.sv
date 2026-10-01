// fft_biplex_real_4x — biplex FFT of 4·N_BIPLEX_INPUTS real signals
//
// Corresponds to casper_library's fft_biplex_real_4x (fixed point, sync mode,
// fft_biplex_real_4x_init.m); casper's n_inputs is N_BIPLEX_INPUTS here.
// Real inputs pol<i>_in are paired into complex signals (ri_to_c) and fed
// to a biplex_core; bi_real_unscr_4x then separates the four real spectra:
//
//   lane j (j = 0 … N_BIPLEX_INPUTS-1):
//     biplex_core pol1 (even_bussify) = pol<4j>_in   + j·pol<4j+1>_in
//     biplex_core pol2 (odd_bussify)  = pol<4j+2>_in + j·pol<4j+3>_in
//   biplex_core sync_out / out1 / out2 ─► bi_real_unscr_4x sync / even / odd
//   pol<i>_out = bi_real_unscr_4x pol<(i mod 4)+1>_out, lane floor(i/4)
//              = the spectrum of pol<i>_in (complex, one bin per cycle)
//   of = biplex_core's of (bypasses bi_real_unscr_4x)
//
// (casper: pol<i-1>_in / pol<i>_in for odd i form ri_to_c floor(i/2), which
// goes to even_bussify if mod((i+1)/2, 2) == 1, else to odd_bussify, port
// floor(i/4)+1; pol<i>_out comes from pol<i mod 4>_debus port floor(i/4)+1.)
//
// Derived as fft_biplex_real_4x_init.m does (F = FFT_SIZE, IW = INPUT_BIT_WIDTH):
//   bram_delays = 2^(F-1)·2·IW·N_BIPLEX_INPUTS >= 2^DELAYS_BIT_LIMIT
//                 && 2^(F-1) >= BRAM_LATENCY+2
//   bram_map    = 2^(F-1)·(F-1) >= 2^COEFFS_BIT_LIMIT && 2^(F-1) >= BRAM_LATENCY
//   output width: BITGROWTH ? min(IW+F, MAX_BITS) : IW, binary point BIN_PT_IN
//
// Memory files: biplex_core reads COEFF_DIR + "twiddle_stage<s>.mem",
// bi_real_unscr_4x reads MAP_DIR + "map_even.mem" / "map_odd.mem" /
// "map_out.mem" (rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py,
// rtl/Reorder/scripts/gen_reorder_map.py --bi-real).
//
// of[n] is lane n's overflow (biplex_core's convention). The inputs need a
// sync once per 2^FFT_SIZE-cycle frame (or a multiple), as bi_real_unscr_4x's
// reorders require. Declared for traceability only: ASYNC must be 0;
// COEFF_SHARING, COEFF_DECIMATION, MULT_SPEC, DSP48_ADDERS, ADD_PIPE_LATENCY
// and MULT_PIPE_LATENCY are ignored.

module fft_biplex_real_4x #(
    parameter int    N_BIPLEX_INPUTS   = 1,
    parameter int    FFT_SIZE          = 2,
    parameter int    INPUT_BIT_WIDTH   = 18,
    parameter int    BIN_PT_IN         = 17,
    parameter int    COEFF_BIT_WIDTH   = 18,
    parameter int    ADD_LATENCY       = 1,
    parameter int    MULT_LATENCY      = 2,
    parameter int    BRAM_LATENCY      = 2,
    parameter int    CONV_LATENCY      = 1,
    parameter int    QUANTIZATION      = 1,
    parameter int    OVERFLOW          = 1,
    parameter int    DELAYS_BIT_LIMIT  = 8,
    parameter int    COEFFS_BIT_LIMIT  = 8,
    parameter int    MAX_FANOUT        = 4,
    parameter int    BITGROWTH         = 0,
    parameter int    MAX_BITS          = 19,
    parameter int    HARDCODE_SHIFTS   = 0,
    parameter int    SHIFT_SCHEDULE    = 3,
    parameter string COEFF_DIR         = "",
    parameter string MAP_DIR           = "",
    parameter string PLATFORM          = "GENERIC",
    // declared, not implemented (see header)
    parameter int    ASYNC             = 0,
    parameter int    ADD_PIPE_LATENCY  = 0,
    parameter int    MULT_PIPE_LATENCY = 0,
    parameter int    COEFF_SHARING     = 1,
    parameter int    COEFF_DECIMATION  = 1,
    parameter int    MULT_SPEC         = 2,
    parameter int    DSP48_ADDERS      = 0,
    // output width, derived (not meant to be overridden)
    parameter int    N_BITS_OUT        = (BITGROWTH != 0) ? ((INPUT_BIT_WIDTH + FFT_SIZE < MAX_BITS)
                                         ? INPUT_BIT_WIDTH + FFT_SIZE : MAX_BITS) : INPUT_BIT_WIDTH
)(
    input  logic                       clk,
    input  logic                       sync,
    input  logic [FFT_SIZE-1:0]        shift,
    input  logic [INPUT_BIT_WIDTH-1:0] pol_in     [4 * N_BIPLEX_INPUTS],
    output logic                       sync_out,
    output logic [N_BITS_OUT-1:0]      pol_out_re [4 * N_BIPLEX_INPUTS],
    output logic [N_BITS_OUT-1:0]      pol_out_im [4 * N_BIPLEX_INPUTS],
    output logic [N_BIPLEX_INPUTS-1:0] of
);

    localparam int NB          = N_BIPLEX_INPUTS;
    localparam int IW          = INPUT_BIT_WIDTH;
    localparam longint HALF    = longint'(1) << (FFT_SIZE - 1);
    localparam longint BITS_L  = longint'(2) * longint'(IW) * longint'(NB);
    localparam longint STAGES  = longint'(FFT_SIZE) - 1;
    localparam longint BLAT    = longint'(BRAM_LATENCY);
    localparam int BRAM_DELAYS = (HALF * BITS_L >= (longint'(1) << DELAYS_BIT_LIMIT)
                                  && HALF >= BLAT + 2) ? 1 : 0;
    localparam int BRAM_MAP    = (HALF * STAGES >= (longint'(1) << COEFFS_BIT_LIMIT)
                                  && HALF >= BLAT) ? 1 : 0;

    if (ASYNC != 0) $fatal(1, "fft_biplex_real_4x: ASYNC is not implemented");

    logic [IW-1:0]         ev_re [NB], ev_im [NB], od_re [NB], od_im [NB];
    logic [N_BITS_OUT-1:0] b1_re [NB], b1_im [NB], b2_re [NB], b2_im [NB];
    logic [N_BITS_OUT-1:0] p_re [4][NB], p_im [4][NB];
    logic                  b_sync;

    for (genvar j = 0; j < NB; j++) begin : GEN_IN
        assign ev_re[j] = pol_in[4*j];
        assign ev_im[j] = pol_in[4*j + 1];
        assign od_re[j] = pol_in[4*j + 2];
        assign od_im[j] = pol_in[4*j + 3];
    end

    biplex_core #(
        .N_INPUTS(NB), .FFT_SIZE(FFT_SIZE), .INPUT_BIT_WIDTH(IW), .BIN_PT_IN(BIN_PT_IN),
        .COEFF_BIT_WIDTH(COEFF_BIT_WIDTH), .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY),
        .BRAM_LATENCY(BRAM_LATENCY), .CONV_LATENCY(CONV_LATENCY),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .DELAYS_BIT_LIMIT(DELAYS_BIT_LIMIT),
        .MAX_FANOUT(MAX_FANOUT), .BITGROWTH(BITGROWTH), .MAX_BITS(MAX_BITS),
        .HARDCODE_SHIFTS(HARDCODE_SHIFTS), .SHIFT_SCHEDULE(SHIFT_SCHEDULE),
        .COEFF_DIR(COEFF_DIR), .PLATFORM(PLATFORM), .COEFFS_BIT_LIMIT(COEFFS_BIT_LIMIT)
    ) u_biplex_core (
        .clk(clk),
        .pol1_re(ev_re), .pol1_im(ev_im), .pol2_re(od_re), .pol2_im(od_im),
        .sync(sync), .shift(shift),
        .out1_re(b1_re), .out1_im(b1_im), .out2_re(b2_re), .out2_im(b2_im),
        .of(of), .sync_out(b_sync));

    bi_real_unscr_4x #(
        .N_INPUTS(NB), .FFT_SIZE(FFT_SIZE), .N_BITS(N_BITS_OUT), .BIN_PT(BIN_PT_IN),
        .ADD_LATENCY(ADD_LATENCY), .CONV_LATENCY(CONV_LATENCY), .BRAM_LATENCY(BRAM_LATENCY),
        .BRAM_MAP(BRAM_MAP), .BRAM_DELAYS(BRAM_DELAYS), .MAP_DIR(MAP_DIR), .PLATFORM(PLATFORM)
    ) u_bi_real_unscr_4x (
        .clk(clk), .sync(b_sync),
        .even_re(b1_re), .even_im(b1_im), .odd_re(b2_re), .odd_im(b2_im),
        .sync_out(sync_out),
        .pol1_out_re(p_re[0]), .pol1_out_im(p_im[0]), .pol2_out_re(p_re[1]), .pol2_out_im(p_im[1]),
        .pol3_out_re(p_re[2]), .pol3_out_im(p_im[2]), .pol4_out_re(p_re[3]), .pol4_out_im(p_im[3]));

    for (genvar i = 0; i < 4 * NB; i++) begin : GEN_OUT
        assign pol_out_re[i] = p_re[i % 4][i / 4];
        assign pol_out_im[i] = p_im[i % 4][i / 4];
    end

endmodule
