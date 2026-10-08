// biplex_core — streaming biplex FFT core: a chain of FFT_SIZE fft_stage_n
//
// Corresponds to casper_library's biplex_core (fixed-point, synchronous),
// built as biplex_core_init.m draws it: stage 1 takes pol1 / pol2, of_in = 0
// and sync; every later stage takes the previous stage's out1 / out2 / of /
// sync_out; all stages share the shift bus. The last stage drives the
// outputs. Output order is that of casper's biplex_core (bit-reversed,
// unscrambled later by the fft_biplex_real / fft_wideband_real wrappers).
//
// Per stage s (1 .. FFT_SIZE), derived exactly as biplex_core_init.m does:
//   DELAYS_BRAM   = (FFT_SIZE - s > DELAYS_BIT_LIMIT) && (2^(FFT_SIZE-s) > BRAM_LATENCY)
//                   (casper compares against num2str(bram_latency), i.e. the
//                   character code; identical whenever DELAYS_BIT_LIMIT >= 5)
//   DOWNSHIFT     = HARDCODE_SHIFTS && SHIFT_SCHEDULE[s-1]
//   input width   = BITGROWTH ? min(MAX_BITS, INPUT_BIT_WIDTH + s - 1) : INPUT_BIT_WIDTH
//   BITGROWTH     = BITGROWTH && (input width + 1 <= MAX_BITS)
//   INIT_FILE     = {COEFF_DIR, "twiddle_stage<s>.mem"} (stages >= 3 use
//                   twiddle_general; generate the files with
//                   rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py --fft-size FFT_SIZE
//                   --coeffs 0 .. 2^(s-1)-1)
// BIN_PT_IN is the same for every stage.
//
// SHIFT_SCHEDULE is casper's shift_schedule vector as a bit mask (bit s-1 =
// stage s), used only with HARDCODE_SHIFTS = 1; otherwise shift[s-1] is
// stage s's dynamic downshift.
//
// Declared for traceability only: ASYNC and FLOATING_POINT must be 0;
// FLOAT_TYPE, EXP_WIDTH, FRAC_WIDTH, ADD_PIPE_LATENCY, MULT_PIPE_LATENCY,
// COEFFS_BIT_LIMIT, COEFF_SHARING, COEFF_DECIMATION, MULT_SPEC and
// DSP48_ADDERS are ignored.
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
// block = 'casper_library_ffts.slx/biplex_core'
// deviations = [
//   "The mask's bin_pt_in = -1 backwards-compatibility value (replaced by input_bit_width-1 in biplex_core_init.m:132-136) is not recognised: BIN_PT_IN must be given explicitly.",
//   "Per-stage DELAYS_BRAM is derived numerically (2^(FFT_SIZE-s) > BRAM_LATENCY), but biplex_core_init.m:160 compares 2^(FFTSize-stage) > num2str(bram_latency), i.e. against the character code(s) ('2' = 50); the two agree only when DELAYS_BIT_LIMIT >= 5, otherwise the HDL can choose BRAM delays (adding BRAM_LATENCY of fan-in latency per stage, fft_stage_n.sv P) where Simulink uses registers.",
//   "OVERFLOW = 2 ('Error') has no working Simulink counterpart: butterfly_direct_init.m:512-514 compares the option against 'Flag as error', so 'Error' leaves the bus_convert overflow argument undefined and the mask init fails, whereas the HDL silently wraps (rtl/Bus/convert.sv saturates only for OVERFLOW = 1).",
//   "DSP48_ADDERS is ignored, but in Simulink dsp48_adders = 'on' forces add_latency = 2 in every butterfly_direct (butterfly_direct_init.m:194-197), so with the box ticked and ADD_LATENCY != 2 the Simulink data/sync latency differs from the HDL's.",
//   "ADD_PIPE_LATENCY / MULT_PIPE_LATENCY are ignored: in Simulink a non-zero add_pipe_latency inserts pipeline blocks on the bus_addsub inputs (bus_addsub_init.m:250-275, enabled by butterfly_direct_init.m:156-160) and mult_pipe_latency pipelines twiddle_general's bus_mult (twiddle_general_init.m:250-251), so for non-zero values the HDL has less latency (note Simulink's own fixed-point sync delay, butterfly_direct_init.m:652, does not include add_pipe_latency); only 0 is equivalent.",
//   'Bit order of of: the HDL puts lane 0 in bit 0 (of[n] = lane n), but Simulink packs the per-lane flags with bus_create/Concat, lane 0 in the MSB (butterfly_direct_init.m:625-643 munge + bus_relational -> bussify in1 = MSB, bus_relational_init.m:194); the vector is bit-reversed relative to Simulink when it has more than one bit (fft_wideband_real.sv:31-33 and its GEN_OF loop undo this for the top-level of).',
//   "SHIFT_SCHEDULE is an integer bit mask (bit s-1 = stage s) instead of casper's shift_schedule vector, and MULT_SPEC is a single ignored integer instead of the per-stage vector; convert them when transferring mask values.",
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
// note = "casper's per-stage 0/1 vector becomes a bit mask here: bit k = stage k+1 (bit s-1 = stage s)"
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
// [hdl_only]
// COEFF_DIR = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// N_BITS_OUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// order = 'Simulink inports sync, shift, pol1, pol2 and outports sync_out, out1, out2, of (biplex_core_init.m:141-144, 255-258); the HDL lists pol1/pol2 before sync/shift and sync_out last'
// note = 'each Simulink complex port x is split into x_re / x_im; the Simulink bus pol1/pol2/out1/out2 carries N_INPUTS complex lanes, lane 0 in the MSBs, which become array element 0'
// [ports.renamed]
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module biplex_core #(
    parameter int    N_INPUTS          = 1,
    parameter int    FFT_SIZE          = 3,
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
    parameter int    MAX_FANOUT        = 4,
    parameter int    BITGROWTH         = 1,
    parameter int    MAX_BITS          = 20,
    parameter int    HARDCODE_SHIFTS   = 0,
    parameter int    SHIFT_SCHEDULE    = 3,
    parameter string COEFF_DIR         = "",
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
    parameter int    MULT_SPEC         = 2,
    parameter int    DSP48_ADDERS      = 0,
    // output width, derived (not meant to be overridden)
    parameter int    N_BITS_OUT        = stage_out_width(FFT_SIZE, INPUT_BIT_WIDTH, BITGROWTH, MAX_BITS)
)(
    input  logic                       clk,
    input  logic [INPUT_BIT_WIDTH-1:0] pol1_re [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] pol1_im [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] pol2_re [N_INPUTS],
    input  logic [INPUT_BIT_WIDTH-1:0] pol2_im [N_INPUTS],
    input  logic                       sync,
    input  logic [FFT_SIZE-1:0]        shift,
    output logic [N_BITS_OUT-1:0]      out1_re [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      out1_im [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      out2_re [N_INPUTS],
    output logic [N_BITS_OUT-1:0]      out2_im [N_INPUTS],
    output logic [N_INPUTS-1:0]        of,
    output logic                       sync_out
);

    // input width of stage s (biplex_core_init.m)
    function automatic int stage_in_width(int s, int iw, int bitgrowth, int max_bits);
        if (bitgrowth == 0) return iw;
        return (iw + s - 1 < max_bits) ? iw + s - 1 : max_bits;
    endfunction

    function automatic int stage_grows(int s, int iw, int bitgrowth, int max_bits);
        return (bitgrowth != 0 && stage_in_width(s, iw, bitgrowth, max_bits) + 1 <= max_bits) ? 1 : 0;
    endfunction

    function automatic int stage_out_width(int s, int iw, int bitgrowth, int max_bits);
        return stage_in_width(s, iw, bitgrowth, max_bits) + stage_grows(s, iw, bitgrowth, max_bits);
    endfunction

    // "twiddle_stage<s>.mem" appended to COEFF_DIR (s < 100)
    function automatic string stage_file(string dir, int s);
        string num;
        num = (s >= 10) ? {string'(8'(48 + s / 10)), string'(8'(48 + s % 10))}
                        : string'(8'(48 + s));
        return {dir, "twiddle_stage", num, ".mem"};
    endfunction

    localparam int WMAX = INPUT_BIT_WIDTH + FFT_SIZE;   // widest any stage can be

    if (ASYNC != 0)          $fatal(1, "biplex_core: ASYNC is not implemented");
    if (FLOATING_POINT != 0) $fatal(1, "biplex_core: FLOATING_POINT is not implemented");
    if (FFT_SIZE < 2)        $fatal(1, "biplex_core: FFT_SIZE must be >= 2");

    // stage boundary s (0 = core inputs, s = output of stage s), zero-extended
    // to WMAX; each stage uses its own width
    logic [WMAX-1:0]     d1_re [FFT_SIZE+1][N_INPUTS], d1_im [FFT_SIZE+1][N_INPUTS];
    logic [WMAX-1:0]     d2_re [FFT_SIZE+1][N_INPUTS], d2_im [FFT_SIZE+1][N_INPUTS];
    logic [N_INPUTS-1:0] of_c  [FFT_SIZE+1];
    logic                sync_c [FFT_SIZE+1];

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_IN
        assign d1_re[0][n] = WMAX'(pol1_re[n]);
        assign d1_im[0][n] = WMAX'(pol1_im[n]);
        assign d2_re[0][n] = WMAX'(pol2_re[n]);
        assign d2_im[0][n] = WMAX'(pol2_im[n]);
    end
    assign of_c[0]   = '0;
    assign sync_c[0] = sync;

    for (genvar s = 1; s <= FFT_SIZE; s++) begin : GEN_STAGE
        localparam int W_IN  = stage_in_width(s, INPUT_BIT_WIDTH, BITGROWTH, MAX_BITS);
        localparam int GROW  = stage_grows(s, INPUT_BIT_WIDTH, BITGROWTH, MAX_BITS);
        localparam int W_OUT = W_IN + GROW;
        localparam int BRAM  = (FFT_SIZE - s > DELAYS_BIT_LIMIT && (1 << (FFT_SIZE - s)) > BRAM_LATENCY) ? 1 : 0;
        localparam int DOWN  = (HARDCODE_SHIFTS != 0 && ((SHIFT_SCHEDULE >> (s - 1)) & 1) != 0) ? 1 : 0;

        logic [W_IN-1:0]  i1_re [N_INPUTS], i1_im [N_INPUTS], i2_re [N_INPUTS], i2_im [N_INPUTS];
        logic [W_OUT-1:0] o1_re [N_INPUTS], o1_im [N_INPUTS], o2_re [N_INPUTS], o2_im [N_INPUTS];

        for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
            assign i1_re[n] = d1_re[s-1][n][W_IN-1:0];
            assign i1_im[n] = d1_im[s-1][n][W_IN-1:0];
            assign i2_re[n] = d2_re[s-1][n][W_IN-1:0];
            assign i2_im[n] = d2_im[s-1][n][W_IN-1:0];
            assign d1_re[s][n] = WMAX'(o1_re[n]);
            assign d1_im[s][n] = WMAX'(o1_im[n]);
            assign d2_re[s][n] = WMAX'(o2_re[n]);
            assign d2_im[s][n] = WMAX'(o2_im[n]);
        end

        fft_stage_n #(
            .N_INPUTS(N_INPUTS), .FFT_SIZE(FFT_SIZE), .FFT_STAGE(s),
            .INPUT_BIT_WIDTH(W_IN), .BIN_PT_IN(BIN_PT_IN), .COEFF_BIT_WIDTH(COEFF_BIT_WIDTH),
            .BITGROWTH(GROW), .DOWNSHIFT(DOWN), .HARDCODE_SHIFTS(HARDCODE_SHIFTS),
            .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY),
            .BRAM_LATENCY(BRAM_LATENCY), .CONV_LATENCY(CONV_LATENCY),
            .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW),
            .DELAYS_BRAM(BRAM), .MAX_FANOUT(MAX_FANOUT),
            .INIT_FILE(stage_file(COEFF_DIR, s)), .PLATFORM(PLATFORM)
        ) u_stage (
            .clk(clk),
            .in1_re(i1_re), .in1_im(i1_im), .in2_re(i2_re), .in2_im(i2_im),
            .of_in(of_c[s-1]), .sync(sync_c[s-1]), .shift(shift),
            .out1_re(o1_re), .out1_im(o1_im), .out2_re(o2_re), .out2_im(o2_im),
            .of(of_c[s]), .sync_out(sync_c[s]));
    end

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_OUT
        assign out1_re[n] = d1_re[FFT_SIZE][n][N_BITS_OUT-1:0];
        assign out1_im[n] = d1_im[FFT_SIZE][n][N_BITS_OUT-1:0];
        assign out2_re[n] = d2_re[FFT_SIZE][n][N_BITS_OUT-1:0];
        assign out2_im[n] = d2_im[FFT_SIZE][n][N_BITS_OUT-1:0];
    end
    assign of       = of_c[FFT_SIZE];
    assign sync_out = sync_c[FFT_SIZE];

endmodule
