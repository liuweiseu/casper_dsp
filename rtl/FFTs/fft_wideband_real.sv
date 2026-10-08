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
//      fft_biplex_real_4x: its N_INPUTS = NB = NS·2^(NI-2), FFT_SIZE = F-NI
//      (the first F-NI stages), shift = shift (only its low F-NI bits are used)
//   pol<s·2^NI+n>_out ─► pipeline BIPLEX_DIRECT_LATENCY ─► fft_direct in<s><n>
//      fft_direct: N_STREAMS = NS, FFT_SIZE = NI (the last NI stages),
//      MAP_TAIL on, LARGER_FFT_SIZE = F, START_STAGE = F-NI+1,
//      shift = shift[F-1 : F-NI]
//   fft_direct out<s><n>, n < 2^(NI-1) (the upper half is terminated):
//      UNSCRAMBLE: ─► pipeline BIPLEX_DIRECT_LATENCY ─► fft_unscrambler
//                  (FFT_SIZE = F-1, its N_INPUTS = NI-1, N_STREAMS = NS)
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
// NB bits (lane 0 = MSB), fft_direct's N_STREAMS bits (stream 0 = MSB), so
// of has max of the two widths, bit b = biplex lane NB-1-b | fft_direct
// stream N_STREAMS-1-b (missing bits 0).
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
// block = 'casper_library_ffts.slx/fft_wideband_real'
// deviations = [
//   "fft_direct part: cOEFF_GENERATION / CAL_BITS / N_BITS_ROTATION are ignored and the twiddles always come from ROM tables, but in Simulink coeff_generation = 'on' (mask default) makes coeff_gen build a feedback_osc phase-rotation oscillator instead of a lookup table whenever the butterfly's Coeffs list is bit-reversed and log2(length(Coeffs)) > ceil(log2(mult_latency+add_latency+conv_latency+1)) + cal_bits (coeff_gen_init.m:260, 308, 497-530); the oscillator's twiddle values are not the exactly rounded table values, so outputs can differ in the LSBs (each fft_direct butterfly here has 2^(FFT_SIZE-N_INPUTS) bit-reversed coefficients, so typical sizes qualify; unverified numerically); the biplex stages are unaffected (fft_stage_n_init.m:501 forces coeff_generation off).",
//   "With BITGROWTH = 1 and INPUT_BIT_WIDTH+FFT_SIZE < MAX_BITS, Simulink's fft_direct slices its outputs with the wrong width (fft_direct_init.m:228 '*' typo), which the HDL deliberately does not reproduce (fft_direct.sv:35-38).",
//   "The mask's bin_pt_in = -1 backwards-compatibility value (replaced by input_bit_width-1 in fft_wideband_real_init.m:178-182) is not recognised: BIN_PT_IN must be given explicitly.",
//   "Inherits biplex_core's DELAYS_BRAM derivation, which differs from Simulink's character-code comparison (biplex_core_init.m:160) when DELAYS_BIT_LIMIT < 5, changing the biplex latency.",
//   "OVERFLOW = 2 ('Error') has no working Simulink counterpart: butterfly_direct_init.m:512-514 compares the option against 'Flag as error', so 'Error' leaves the bus_convert overflow argument undefined and the mask init fails, whereas the HDL silently wraps (rtl/Bus/convert.sv saturates only for OVERFLOW = 1).",
//   "DSP48_ADDERS is ignored, but in Simulink dsp48_adders = 'on' forces add_latency = 2 in every butterfly_direct (butterfly_direct_init.m:194-197), so with the box ticked and ADD_LATENCY != 2 the Simulink data/sync latency differs from the HDL's.",
//   "ADD_PIPE_LATENCY / MULT_PIPE_LATENCY are ignored: in Simulink a non-zero add_pipe_latency inserts pipeline blocks on the bus_addsub inputs (bus_addsub_init.m:250-275, enabled by butterfly_direct_init.m:156-160) and mult_pipe_latency pipelines twiddle_general's bus_mult (twiddle_general_init.m:250-251), so for non-zero values the HDL has less latency (note Simulink's own fixed-point sync delay, butterfly_direct_init.m:652, does not include add_pipe_latency); only 0 is equivalent.",
//   "SHIFT_SCHEDULE is an integer bit mask (bit k = stage k+1) instead of casper's shift_schedule vector (sliced in fft_wideband_real_init.m:214-219), and MULT_SPEC is a single ignored integer instead of the per-stage vector.",
// ]
//
// [params.UNSCRAMBLE]
// mask = 'unscramble'
// type = 'checkbox'
// note = 'treated as off when N_INPUTS = 1, as in fft_wideband_real_init.m:189-191'
// [params.UNSCRAMBLE.values]
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
// [params.BITGROWTH]
// mask = 'bitgrowth'
// type = 'checkbox'
// [params.BITGROWTH.values]
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
// [params.SHIFT_SCHEDULE]
// mask = 'shift_schedule'
// type = 'edit'
// note = "casper's per-stage 0/1 vector becomes a bit mask here: bit k = stage k+1 (bit k = stage k+1; low FFT_SIZE-N_INPUTS bits go to the biplex part)"
//
// [params.MULT_SPEC]
// mask = 'mult_spec'
// type = 'edit'
// note = "casper's per-stage vector (multiplier_specification.m) becomes one ignored scalar; implementation-only (multiplier core choice)"
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
// note = 'ignored: the HDL always reads ROM tables (see deviations)'
// [params.COEFF_GENERATION.values]
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
// [hdl_only]
// MEM_DIR = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// N_BITS_OUT = 'derived from other parameters (do not override)'
// OF_WIDTH = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// note = 'din element s*2^N_INPUTS + n is in<s><n>, dout element s*2^(N_INPUTS-1) + n is out<s><n>; each Simulink complex port x is split into x_re / x_im; of is the LSB-aligned OR of the biplex and direct of vectors with lane / stream 0 in the MSB, as in Simulink'
// [ports.renamed]
// din = 'in<s><n>'
// dout_re = 'out<s><n>'
// dout_im = 'out<s><n>'
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

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
    localparam int NB     = (NS << NI) / 4;              // fft_biplex_real_4x N_INPUTS
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

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(INPUT_LATENCY)) u_in_del_sync_4x (
        .clk(clk), .din(sync), .dout(sync_d));
    for (genvar k = 0; k < NIN; k++) begin : GEN_IN_DEL
        pipeline #(.BITWIDTH(INPUT_BIT_WIDTH), .CSP_LATENCY(INPUT_LATENCY)) u_in_del_4x_pol (
            .clk(clk), .din(din[k]), .dout(din_d[k]));
    end

    // ── first F-NI stages: fft_biplex_real_4x ────────────────────────────────
    logic [W_DIR-1:0] bx_re [NIN], bx_im [NIN], bxd_re [NIN], bxd_im [NIN];
    logic [NB-1:0]    bx_of;
    logic             bx_sync, bxd_sync;

    fft_biplex_real_4x #(
        .N_INPUTS(NB), .FFT_SIZE(FB), .INPUT_BIT_WIDTH(INPUT_BIT_WIDTH),
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

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(BIPLEX_DIRECT_LATENCY)) u_del_sync_4x (
        .clk(clk), .din(bx_sync), .dout(bxd_sync));
    for (genvar k = 0; k < NIN; k++) begin : GEN_BX_DEL
        pipeline #(.BITWIDTH(2 * W_DIR), .CSP_LATENCY(BIPLEX_DIRECT_LATENCY)) u_del_4x_pol (
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

        pipeline #(.BITWIDTH(1), .CSP_LATENCY(BIPLEX_DIRECT_LATENCY)) u_fft_direct_sync_delay (
            .clk(clk), .din(fd_sync), .dout(fd_sync_d));
        for (genvar k = 0; k < NOUT; k++) begin : GEN_DEL_DIRECT
            pipeline #(.BITWIDTH(2 * N_BITS_OUT), .CSP_LATENCY(BIPLEX_DIRECT_LATENCY)) u_del_direct (
                .clk(clk), .din({kept_im[k], kept_re[k]}), .dout({kd_im[k], kd_re[k]}));
        end

        fft_unscrambler #(
            .N_STREAMS(NS), .FFT_SIZE(F - 1), .N_INPUTS(NI - 1), .N_BITS_IN(N_BITS_OUT),
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
