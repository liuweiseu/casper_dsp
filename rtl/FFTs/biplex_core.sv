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
