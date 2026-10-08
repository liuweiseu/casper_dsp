// fft_direct — fully parallel radix-2 FFT of 2^FFT_SIZE inputs per stream
//
// Corresponds to casper_library's fft_direct (fixed point, sync mode,
// fft_direct_init.m). Every cycle, each of the N_STREAMS streams presents
// 2^FFT_SIZE complex samples in<s><n>; FFT_SIZE stages of butterfly_direct
// (BIPLEX off, STEP_PERIOD 0) transform them, and the outputs come out in
// natural order. As fft_direct_init.m wires it (F = FFT_SIZE):
//
//   stage 0: one butterfly of N_STREAMS·2^(F-1) lanes; lane idx = n·N_STREAMS + s
//            of input in<s><n>: a = idx < N_STREAMS·2^(F-1), b = the rest
//   stage s: 2^s butterflies of L = N_STREAMS·2^(F-s-1) lanes; butterfly
//            2u+c of stage s+1 takes butterfly u's a+bw (c = 0) or a−bw
//            (c = 1), a = its upper (MSB) half lanes, b = the lower half
//   output : out<s><n> = stream s of position p = bit_rev(n, F) of the last
//            stage (butterfly p>>1, a+bw if p even, a−bw if odd)
//   shift  : stage s uses shift[s]; downshift = HARDCODE_SHIFTS && SHIFT_SCHEDULE bit s
//   sync   : stage-0 butterfly gets sync, butterfly 2u+c the sync_out of u;
//            sync_out = sync_out of the last stage's butterfly 0
//
// Coefficients of butterfly u of stage s (n = u·2^(F-s-1)), a time sequence
// stepped every cycle (STEP_PERIOD 0) and restarted by sync:
//   MAP_TAIL = 0: Coeffs = [floor(n / 2^(F-(s+1)))] = [u], FFT size F
//   MAP_TAIL = 1: Coeffs[r] = floor((n + bit_reverse(r, LARGER-F)·2^(F-1))
//                                   / 2^(LARGER-(START_STAGE+s))),
//                 r = 0 … 2^(LARGER-F)-1, FFT size LARGER_FFT_SIZE
//                 (the last F stages of a LARGER_FFT_SIZE-point FFT whose
//                 earlier stages ran as a biplex FFT, as in fft_wideband_real)
// butterfly_direct picks its twiddle from them (coeff_0, coeff_1 or general);
// a general twiddle reads COEFF_DIR + "twiddle_direct_s<s>_<u>.mem", made by
// rtl/FFTs/scripts/gen_fft_direct_coeffs.py.
//
// Widths: stage s takes W(s) = BITGROWTH ? min(MAX_BITS, INPUT_BIT_WIDTH+s) :
// INPUT_BIT_WIDTH and grows one bit if BITGROWTH and W(s)+1 <= MAX_BITS; the
// outputs are W(F-1) + grow bits.
// DELIBERATE DEVIATION: fft_direct_init.m sizes the output bus_expands with
// n_bits = min(max_bits, input_bit_width*FFTSize) for bitgrowth on (a '*'
// typo for '+', in the "for n=0:2^FFTSize-1" debus loop), which would slice
// the outputs wrongly; this module uses the real output width instead.
//
// of: per stage, the butterflies' of are concatenated (positions u·L + l,
// butterfly 0 lane 0 first); the stages are ORed bitwise (Logical, latency
// 2), split into 2^(F-1) parts of N_STREAMS bits and ORed again (latency 2).
// Position j of a part always belongs to stream j, so of[s] is stream s's
// overflow, 4 cycles after the butterflies' of (F = 1: the butterfly's of).
// Port order: element k of din / dout is in<s><n> / out<s><n> with
// k = s·2^F + n (casper port order).
//
// Declared for traceability only: ASYNC must be 0; COEFFS_BIT_LIMIT,
// COEFF_SHARING, COEFF_DECIMATION, COEFF_GENERATION, CAL_BITS,
// N_BITS_ROTATION, MULT_SPEC, DSP48_ADDERS, ADD_PIPE_LATENCY and
// MULT_PIPE_LATENCY are ignored.
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
// block = 'casper_library_ffts.slx/fft_direct'
// deviations = [
//   "Deliberate: with bitgrowth on, fft_direct_init.m:228 sizes the final output bus_expands as min(max_bits, input_bit_width*FFTSize) ('*' typo for '+'), which mis-slices the outputs whenever input_bit_width+FFTSize < max_bits; the HDL uses the real width min(MAX_BITS, INPUT_BIT_WIDTH+FFT_SIZE) (fft_direct.sv:35-38), so Simulink is not reproduced in that case.",
//   "COEFF_GENERATION / CAL_BITS / N_BITS_ROTATION are ignored and the twiddles always come from ROM tables, but in Simulink coeff_generation = 'on' (mask default) makes coeff_gen build a feedback_osc phase-rotation oscillator instead of a lookup table whenever the butterfly's Coeffs list is bit-reversed and log2(length(Coeffs)) > ceil(log2(mult_latency+add_latency+conv_latency+1)) + cal_bits (coeff_gen_init.m:260, 308, 497-530); the oscillator's twiddle values are not the exactly rounded table values, so outputs can differ in the LSBs (MAP_TAIL = 1 lists of 2^(LARGER_FFT_SIZE-FFT_SIZE) bit-reversed coefficients typically qualify; unverified numerically).",
//   'With MAP_TAIL = 0 and FFT_SIZE >= 3, every butterfly whose single coefficient index u is >= 2 uses a constant twiddle_general, which casper quantizes to coeff_bit_width-2 fraction bits (coeff_gen_init.m:156-157) while the HDL table (written by rtl/FFTs/scripts/gen_fft_mem_files.py via gen_twiddle_coeffs.py:52) uses coeff_bit_width-1 fraction bits, so those twiddles can differ by one coefficient LSB (known, left unchanged; mlib_devel_notes/fft_wideband_real_hdl_plan.md Phase 6).',
//   "The mask's bin_pt_in = -1 backwards-compatibility value (replaced by input_bit_width-1 in fft_direct_init.m:187-190) is not recognised: BIN_PT_IN must be given explicitly.",
//   "OVERFLOW = 2 ('Error') has no working Simulink counterpart: butterfly_direct_init.m:512-514 compares the option against 'Flag as error', so 'Error' leaves the bus_convert overflow argument undefined and the mask init fails, whereas the HDL silently wraps (rtl/Bus/convert.sv saturates only for OVERFLOW = 1).",
//   "DSP48_ADDERS is ignored, but in Simulink dsp48_adders = 'on' forces add_latency = 2 in every butterfly_direct (butterfly_direct_init.m:194-197), so with the box ticked and ADD_LATENCY != 2 the Simulink data/sync latency differs from the HDL's.",
//   "ADD_PIPE_LATENCY / MULT_PIPE_LATENCY are ignored: in Simulink a non-zero add_pipe_latency inserts pipeline blocks on the bus_addsub inputs (bus_addsub_init.m:250-275, enabled by butterfly_direct_init.m:156-160) and mult_pipe_latency pipelines twiddle_general's bus_mult (twiddle_general_init.m:250-251), so for non-zero values the HDL has less latency (note Simulink's own fixed-point sync delay, butterfly_direct_init.m:652, does not include add_pipe_latency); only 0 is equivalent.",
//   "Bit order of of: the HDL puts stream 0 in bit 0 (of[n] = stream n), but Simulink packs the per-stream flags with bus_create/Concat, stream 0 in the MSB (fft_direct_init.m:336 Concat of the butterflies' of buses, Concat input 1 = MSB, then of_expand / combine); the vector is bit-reversed relative to Simulink when it has more than one bit (fft_wideband_real.sv:31-33 and its GEN_OF loop undo this for the top-level of).",
//   "SHIFT_SCHEDULE is an integer bit mask (bit s = stage s) instead of casper's shift_schedule vector, and MULT_SPEC is a single ignored integer instead of the per-stage vector.",
// ]
//
// [params.MAP_TAIL]
// mask = 'map_tail'
// type = 'checkbox'
// [params.MAP_TAIL.values]
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
// note = "casper's per-stage 0/1 vector becomes a bit mask here: bit k = stage k+1 (bit s = stage s, s = 0 .. FFT_SIZE-1)"
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
// COEFF_DIR = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// N_BITS_OUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
// floating_point = 'floating point is not implemented'
// float_type = 'floating point is not implemented'
// exp_width = 'floating point is not implemented'
// frac_width = 'floating point is not implemented'
//
// [ports]
// note = 'array element s*2^FFT_SIZE + n; each Simulink complex port x is split into x_re / x_im'
// [ports.renamed]
// din_re = 'in<s><n>'
// din_im = 'in<s><n>'
// dout_re = 'out<s><n>'
// dout_im = 'out<s><n>'
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module fft_direct #(
    parameter int    N_STREAMS         = 1,
    parameter int    FFT_SIZE          = 2,
    parameter int    INPUT_BIT_WIDTH   = 18,
    parameter int    BIN_PT_IN         = 17,
    parameter int    COEFF_BIT_WIDTH   = 18,
    parameter int    MAP_TAIL          = 1,
    parameter int    LARGER_FFT_SIZE   = 12,
    parameter int    START_STAGE       = 10,
    parameter int    ADD_LATENCY       = 1,
    parameter int    MULT_LATENCY      = 2,
    parameter int    BRAM_LATENCY      = 2,
    parameter int    CONV_LATENCY      = 1,
    parameter int    QUANTIZATION      = 1,
    parameter int    OVERFLOW          = 1,
    parameter int    MAX_FANOUT        = 4,
    parameter int    BITGROWTH         = 0,
    parameter int    MAX_BITS          = 19,
    parameter int    HARDCODE_SHIFTS   = 1,
    parameter int    SHIFT_SCHEDULE    = 3,
    parameter string COEFF_DIR         = "",
    parameter string PLATFORM          = "GENERIC",
    // declared, not implemented (see header)
    parameter int    ASYNC             = 0,
    parameter int    ADD_PIPE_LATENCY  = 0,
    parameter int    MULT_PIPE_LATENCY = 0,
    parameter int    COEFFS_BIT_LIMIT  = 9,
    parameter int    COEFF_SHARING     = 1,
    parameter int    COEFF_DECIMATION  = 1,
    parameter int    COEFF_GENERATION  = 1,
    parameter int    CAL_BITS          = 1,
    parameter int    N_BITS_ROTATION   = 25,
    parameter int    MULT_SPEC         = 2,
    parameter int    DSP48_ADDERS      = 0,
    // output width, derived (not meant to be overridden)
    parameter int    N_BITS_OUT        = out_width(FFT_SIZE, INPUT_BIT_WIDTH, BITGROWTH, MAX_BITS)
)(
    input  logic                       clk,
    input  logic                       sync,
    input  logic [FFT_SIZE-1:0]        shift,
    input  logic [INPUT_BIT_WIDTH-1:0] din_re  [N_STREAMS << FFT_SIZE],
    input  logic [INPUT_BIT_WIDTH-1:0] din_im  [N_STREAMS << FFT_SIZE],
    output logic                       sync_out,
    output logic [N_BITS_OUT-1:0]      dout_re [N_STREAMS << FFT_SIZE],
    output logic [N_BITS_OUT-1:0]      dout_im [N_STREAMS << FFT_SIZE],
    output logic [N_STREAMS-1:0]       of
);

    // ── elaboration-time helpers ────────────────────────────────────────────
    function automatic int stage_in_width(int s, int iw, int bitgrowth, int max_bits);
        if (bitgrowth == 0) return iw;
        return (iw + s < max_bits) ? iw + s : max_bits;
    endfunction

    function automatic int stage_grows(int s, int iw, int bitgrowth, int max_bits);
        return (bitgrowth != 0 && stage_in_width(s, iw, bitgrowth, max_bits) + 1 <= max_bits) ? 1 : 0;
    endfunction

    function automatic int out_width(int f, int iw, int bitgrowth, int max_bits);
        return stage_in_width(f - 1, iw, bitgrowth, max_bits) + stage_grows(f - 1, iw, bitgrowth, max_bits);
    endfunction

    function automatic int bit_rev(int v, int bits);
        int r = 0;
        for (int i = 0; i < bits; i++) r |= ((v >> i) & 1) << (bits - 1 - i);
        return r;
    endfunction

    // casper Coeffs entry r of butterfly u of stage s
    function automatic int coeff(int s, int u, int r);
        int n   = u << (FFT_SIZE - s - 1);
        int sh;
        int num;
        if (MAP_TAIL == 0) return n >> (FFT_SIZE - (s + 1));
        num = n + (bit_rev(r, LARGER_FFT_SIZE - FFT_SIZE) << (FFT_SIZE - 1));
        sh  = LARGER_FFT_SIZE - (START_STAGE + s);
        return (sh >= 0) ? (num >> sh) : (num << (-sh));
    endfunction

    function automatic string itoa(int v);
        string str = "";
        if (v == 0) return "0";
        while (v > 0) begin
            str = {string'(8'(48 + v % 10)), str};
            v   = v / 10;
        end
        return str;
    endfunction

    localparam int F        = FFT_SIZE;
    localparam int NS       = N_STREAMS;
    localparam int HALF     = 1 << (F - 1);
    localparam int L0       = NS * HALF;                     // lanes of stage 0
    localparam int N_COEFFS = (MAP_TAIL != 0) ? 1 << (LARGER_FFT_SIZE - FFT_SIZE) : 1;
    localparam int TW_SIZE  = (MAP_TAIL != 0) ? LARGER_FFT_SIZE : FFT_SIZE;

    if (ASYNC != 0) $fatal(1, "fft_direct: ASYNC is not implemented");
    if (F < 1)      $fatal(1, "fft_direct: FFT_SIZE must be >= 1");
    if (MAP_TAIL != 0 && LARGER_FFT_SIZE < FFT_SIZE)
        $fatal(1, "fft_direct: LARGER_FFT_SIZE must be >= FFT_SIZE");

    // butterflies are chained by hierarchical references to the parent's
    // outputs (GEN_STAGE[s-1].GEN_BF[u/2].o1_* / o2_*); the parent's output
    // width W_OUT(s-1) equals this stage's W_IN(s)
    logic [L0-1:0]   bf_of   [F][HALF];

    for (genvar s = 0; s < F; s++) begin : GEN_STAGE
        localparam int L     = NS << (F - s - 1);
        localparam int W_IN  = stage_in_width(s, INPUT_BIT_WIDTH, BITGROWTH, MAX_BITS);
        localparam int GROW  = stage_grows(s, INPUT_BIT_WIDTH, BITGROWTH, MAX_BITS);
        localparam int W_OUT = W_IN + GROW;
        localparam int DOWN  = (HARDCODE_SHIFTS != 0 && ((SHIFT_SCHEDULE >> s) & 1) != 0) ? 1 : 0;

        for (genvar u = 0; u < (1 << s); u++) begin : GEN_BF
            localparam int C0 = coeff(s, u, 0);
            localparam int C1 = (N_COEFFS > 1) ? coeff(s, u, 1) : 0;

            logic [W_IN-1:0]  a_re [L], a_im [L], b_re [L], b_im [L];
            logic [W_OUT-1:0] o1_re [L], o1_im [L], o2_re [L], o2_im [L];
            logic [L-1:0]     o_of;
            logic             s_in, s_out;

            for (genvar l = 0; l < L; l++) begin : GEN_LANE
                if (s == 0) begin : GEN_FIRST
                    // lane idx = n·NS + st of input in<st><n>: a = first L lanes
                    assign a_re[l] = din_re[(l % NS) * (1 << F) + l / NS];
                    assign a_im[l] = din_im[(l % NS) * (1 << F) + l / NS];
                    assign b_re[l] = din_re[((l + L0) % NS) * (1 << F) + (l + L0) / NS];
                    assign b_im[l] = din_im[((l + L0) % NS) * (1 << F) + (l + L0) / NS];
                end else if (u % 2 == 0) begin : GEN_FROM_P
                    assign a_re[l] = GEN_STAGE[s-1].GEN_BF[u/2].o1_re[l];
                    assign a_im[l] = GEN_STAGE[s-1].GEN_BF[u/2].o1_im[l];
                    assign b_re[l] = GEN_STAGE[s-1].GEN_BF[u/2].o1_re[l + L];
                    assign b_im[l] = GEN_STAGE[s-1].GEN_BF[u/2].o1_im[l + L];
                end else begin : GEN_FROM_Q
                    assign a_re[l] = GEN_STAGE[s-1].GEN_BF[u/2].o2_re[l];
                    assign a_im[l] = GEN_STAGE[s-1].GEN_BF[u/2].o2_im[l];
                    assign b_re[l] = GEN_STAGE[s-1].GEN_BF[u/2].o2_re[l + L];
                    assign b_im[l] = GEN_STAGE[s-1].GEN_BF[u/2].o2_im[l + L];
                end
            end

            // sync chain: stage 0 gets sync, butterfly 2u+c the sync_out of u
            if (s == 0) begin : GEN_SYNC_IN
                assign s_in = sync;
            end else begin : GEN_SYNC_CHAIN
                assign s_in = GEN_STAGE[s-1].GEN_BF[u/2].s_out;
            end
            assign bf_of[s][u] = L0'(o_of);

            butterfly_direct #(
                .N_INPUTS(L), .BIPLEX(0), .FFT_SIZE(TW_SIZE), .N_COEFFS(N_COEFFS),
                .COEFF_0(C0), .COEFF_1(C1), .STEP_PERIOD(0),
                .INIT_FILE({COEFF_DIR, "twiddle_direct_s", itoa(s), "_", itoa(u), ".mem"}),
                .COEFF_BIT_WIDTH(COEFF_BIT_WIDTH), .INPUT_BIT_WIDTH(W_IN), .BIN_PT_IN(BIN_PT_IN),
                .BITGROWTH(GROW), .DOWNSHIFT(DOWN), .HARDCODE_SHIFTS(HARDCODE_SHIFTS),
                .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY),
                .BRAM_LATENCY(BRAM_LATENCY), .CONV_LATENCY(CONV_LATENCY),
                .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .MAX_FANOUT(MAX_FANOUT),
                .PLATFORM(PLATFORM)
            ) u_butterfly (
                .clk(clk),
                .a_re(a_re), .a_im(a_im), .b_re(b_re), .b_im(b_im),
                .sync_in(s_in), .shift(shift[s]),
                .apbw_re(o1_re), .apbw_im(o1_im), .ambw_re(o2_re), .ambw_im(o2_im),
                .of(o_of), .sync_out(s_out));
        end
    end

    // ── outputs in natural order ─────────────────────────────────────────────
    for (genvar st = 0; st < NS; st++) begin : GEN_OUT_S
        for (genvar n = 0; n < (1 << F); n++) begin : GEN_OUT_N
            localparam int P = bit_rev(n, F);
            if (P % 2 == 0) begin : GEN_P
                assign dout_re[st * (1 << F) + n] = GEN_STAGE[F-1].GEN_BF[P/2].o1_re[st];
                assign dout_im[st * (1 << F) + n] = GEN_STAGE[F-1].GEN_BF[P/2].o1_im[st];
            end else begin : GEN_Q
                assign dout_re[st * (1 << F) + n] = GEN_STAGE[F-1].GEN_BF[P/2].o2_re[st];
                assign dout_im[st * (1 << F) + n] = GEN_STAGE[F-1].GEN_BF[P/2].o2_im[st];
            end
        end
    end
    assign sync_out = GEN_STAGE[F-1].GEN_BF[0].s_out;

    // ── overflow ─────────────────────────────────────────────────────────────
    if (F == 1) begin : GEN_OF_SINGLE
        assign of = bf_of[0][0][NS-1:0];
    end else begin : GEN_OF_TREE
        // per-stage vectors: position e = u·L + l
        logic [L0-1:0] stage_vec [F];
        logic [L0-1:0] or_vec;
        logic [NS-1:0] parts [HALF];

        for (genvar s = 0; s < F; s++) begin : GEN_VEC
            localparam int L = NS << (F - s - 1);
            for (genvar u = 0; u < (1 << s); u++) begin : GEN_BF
                for (genvar l = 0; l < L; l++) begin : GEN_LANE
                    assign stage_vec[s][u * L + l] = bf_of[s][u][l];
                end
            end
        end

        // of_or: Logical OR of the FFT_SIZE stage vectors, latency 2
        logical #(.NBITS(L0), .NINPUTS(F), .LATENCY(2), .FUNC(2)) u_of_or (
            .clk(clk), .din(stage_vec), .dout(or_vec));

        // of_expand: 2^(F-1) parts of NS bits (position j = stream j)
        for (genvar pt = 0; pt < HALF; pt++) begin : GEN_PART
            assign parts[pt] = or_vec[pt * NS +: NS];
        end

        // combine: Logical OR of the parts, latency 2
        logical #(.NBITS(NS), .NINPUTS(HALF), .LATENCY(2), .FUNC(2)) u_combine (
            .clk(clk), .din(parts), .dout(of));
    end

endmodule
