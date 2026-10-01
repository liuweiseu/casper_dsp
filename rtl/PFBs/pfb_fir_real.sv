// pfb_fir_real — polyphase filter bank FIR for real inputs
//
// Corresponds to casper_library's pfb_fir_real (pfb_fir_real_init.m). For
// each polarisation p = 1 … POLS (POLS = 2 if MAKE_BIPLEX else 1) and input
// n = 1 … 2^N_INPUTS, one chain:
//
//   pol<p>_in<n> ─► pfb_coeff_gen (NPUT = n-1)                      (own coefficients)
//                   or, for p = 2 with COEFFS_SHARE: a Delay of
//                   BRAM_LATENCY+1+FAN_LATENCY, using pol 1's coefficients
//     ─► first_tap_real ─► tap_real × (TOTAL_TAPS-2) ─► last_tap_real
//     ─► adder_tree (TOTAL_TAPS inputs, ADD_LATENCY per stage, every adder
//        Fix_ADDER_N_BITS_OUT_ADDER_BIN_PT_OUT, Truncate, Wrap)
//     ─► Scale 2^SCALE_FACTOR ─► Convert Fix_BIT_WIDTH_OUT_(BIT_WIDTH_OUT-1),
//        Wrap, latency CONV_LATENCY ─► pol<p>_out<n>
//
// Every first tap takes its sync from pol 1 / input 1's pfb_coeff_gen;
// sync_out is pol 1 / input 1's adder_tree sync delayed CONV_LATENCY. The
// tap chain computes the windowed presum
//   y_c(f) = Σ_{j ≡ c (mod 2^PFB_SIZE)} h[j]·x[(f-TOTAL_TAPS+1)·2^PFB_SIZE + j]
// (channel c = 2^N_INPUTS·k + n-1 on input n, frame f), see tap_real.
//
// Width accounting (pfb_fir_real_init.m) needs the coefficient values, so
// BIT_GROWTH and the widths derived from it are parameters, computed by
// rtl/PFBs/scripts/gen_pfb_coeffs.py --bit-width-in (which also writes the
// coefficient ROMs into COEFF_DIR):
//   BIT_GROWTH       = nextpow2(max over the sub-filters of Σ|h|, at least 1)
//   ADDER_BIN_PT_OUT = BIT_WIDTH_IN + COEFF_BIT_WIDTH - 2
//   ADDER_N_BITS_OUT = BIT_GROWTH + 1 + ADDER_BIN_PT_OUT
//   SCALE_FACTOR     = -BIT_GROWTH
//   BIT_WIDTH_OUT    = 0 means ADDER_N_BITS_OUT (the mask's convention)
// With all overflow set to Wrap the bit growth suffices by modulo
// arithmetic. The output convert truncates when BIT_WIDTH_OUT >
// ADDER_BIN_PT_OUT, else it uses QUANTIZATION (0 truncate, 1 round ±inf,
// 2 round even); there is no overflow parameter (always Wrap).
//
// Port order: element (p-1)·2^N_INPUTS + (n-1) of din / dout is pol<p>_in<n>
// / pol<p>_out<n>.
//
// Declared for traceability only: WINDOW_TYPE and FWIDTH only shape the
// coefficient files; MULT_SPEC, ADDER_FOLDING, ADDER_IMP and COEFF_DIST_MEM
// (implementation choices) are ignored.

module pfb_fir_real #(
    parameter int    PFB_SIZE         = 5,
    parameter int    TOTAL_TAPS       = 2,
    parameter string WINDOW_TYPE      = "hamming",
    parameter int    N_INPUTS         = 1,
    parameter int    N_POL_BLOCKS     = 1,
    parameter int    MAKE_BIPLEX      = 0,
    parameter int    BIT_WIDTH_IN     = 8,
    parameter int    BIT_WIDTH_OUT    = 0,
    parameter int    COEFF_BIT_WIDTH  = 18,
    parameter int    COEFF_DIST_MEM   = 0,
    parameter int    ADD_LATENCY      = 1,
    parameter int    MULT_LATENCY     = 2,
    parameter int    BRAM_LATENCY     = 2,
    parameter int    FAN_LATENCY      = 1,
    parameter int    CONV_LATENCY     = 1,
    parameter int    QUANTIZATION     = 1,
    parameter real   FWIDTH           = 1.0,
    parameter int    MULT_SPEC        = 2,
    parameter int    ADDER_FOLDING    = 1,
    parameter int    ADDER_IMP        = 0,
    parameter int    COEFFS_SHARE     = 0,
    // from gen_pfb_coeffs.py --bit-width-in (see header)
    parameter int    BIT_GROWTH       = 1,
    parameter int    ADDER_N_BITS_OUT = BIT_GROWTH + 1 + BIT_WIDTH_IN + COEFF_BIT_WIDTH - 2,
    parameter int    ADDER_BIN_PT_OUT = BIT_WIDTH_IN + COEFF_BIT_WIDTH - 2,
    parameter int    SCALE_FACTOR     = -BIT_GROWTH,
    parameter string COEFF_DIR        = "",
    parameter string PLATFORM         = "GENERIC",
    // derived (not meant to be overridden)
    parameter int    N_BITS_OUT       = (BIT_WIDTH_OUT == 0) ? ADDER_N_BITS_OUT : BIT_WIDTH_OUT,
    parameter int    POLS             = (MAKE_BIPLEX != 0) ? 2 : 1
)(
    input  logic                    clk,
    input  logic                    sync,
    input  logic [BIT_WIDTH_IN-1:0] din  [POLS << N_INPUTS],
    output logic                    sync_out,
    output logic [N_BITS_OUT-1:0]   dout [POLS << N_INPUTS]
);

    localparam int NI     = 1 << N_INPUTS;
    localparam int T      = TOTAL_TAPS;
    localparam int CBW    = COEFF_BIT_WIDTH;
    localparam int BW     = BIT_WIDTH_IN;
    localparam int PW     = BW + CBW;                        // tap product width
    localparam int SHARE  = (MAKE_BIPLEX != 0 && COEFFS_SHARE != 0) ? 1 : 0;
    localparam int CG_DLY = BRAM_LATENCY + 1 + FAN_LATENCY;
    // casper: Truncate when BitWidthOut > adder_bin_pt_out, else the mask's quantization
    localparam int OUT_QUANT = (N_BITS_OUT > ADDER_BIN_PT_OUT) ? 0 : QUANTIZATION;

    if (T < 2) $fatal(1, "pfb_fir_real: TOTAL_TAPS must be >= 2");


    for (genvar p = 0; p < POLS; p++) begin : GEN_POL
        for (genvar n = 0; n < NI; n++) begin : GEN_IN
            localparam int K = p * NI + n;

            // this chain's data, coefficient bus and (pfb_coeff_gen) sync;
            // shared coefficients and the first taps' sync are taken from
            // pol 1's chains by hierarchical reference
            logic [BW-1:0]    cg_data;
            logic [T*CBW-1:0] cg_coeff;
            logic             cg_sync;
            logic             adder_sync;

            // ── coefficients ─────────────────────────────────────────────────
            if (p == 1 && SHARE != 0) begin : GEN_SHARED
                pipeline #(.BITWIDTH(BW), .LATENCY(CG_DLY)) u_delay (
                    .clk(clk), .din(din[K]), .dout(cg_data));
                assign cg_coeff = GEN_POL[0].GEN_IN[n].cg_coeff;
                assign cg_sync  = 1'b0;                  // unused
            end else begin : GEN_COEFFS
                logic [CBW-1:0] coeff [T];
                pfb_coeff_gen #(
                    .PFB_SIZE(PFB_SIZE), .COEFF_BIT_WIDTH(CBW), .TOTAL_TAPS(T),
                    .COEFF_DIST_MEM(COEFF_DIST_MEM), .WINDOW_TYPE(WINDOW_TYPE),
                    .BRAM_LATENCY(BRAM_LATENCY), .N_INPUTS(N_INPUTS), .NPUT(n),
                    .FWIDTH(FWIDTH), .FAN_LATENCY(FAN_LATENCY), .DIN_WIDTH(BW),
                    .COEFF_DIR(COEFF_DIR), .PLATFORM(PLATFORM)
                ) u_coeffs (
                    .clk(clk), .sync(sync), .din(din[K]),
                    .sync_out(cg_sync), .dout(cg_data), .coeff(coeff));
                // casper's coeff bus: ROM 1 in the MSBs
                for (genvar a = 0; a < T; a++) begin : GEN_PACK
                    assign cg_coeff[(T-1-a)*CBW +: CBW] = coeff[a];
                end
            end

            // ── taps: data / sync / coefficient bus chained, products to the adder.
            // The coefficient bus is combinational from tap to tap, so it is
            // chained by hierarchical reference (an array would look like a loop).
            logic [PW-1:0]        prod [T];
            logic [BW-1:0]        t_data [T-1];
            logic                 t_sync [T-1];
            logic [(T-1)*CBW-1:0] c_first;

            first_tap_real #(
                .PFB_SIZE(PFB_SIZE), .N_INPUTS(N_INPUTS), .N_POL_BLOCKS(N_POL_BLOCKS),
                .COEFF_BIT_WIDTH(CBW), .TOTAL_TAPS(T), .BIT_WIDTH_IN(BW),
                .MULT_LATENCY(MULT_LATENCY), .BRAM_LATENCY(BRAM_LATENCY), .PLATFORM(PLATFORM)
            ) u_first_tap (
                .clk(clk), .din(cg_data), .sync(GEN_POL[0].GEN_IN[0].cg_sync), .coeff(cg_coeff),
                .dout(t_data[0]), .sync_out(t_sync[0]), .coeff_out(c_first),
                .taps_out(prod[0]));

            for (genvar t = 1; t < T - 1; t++) begin : GEN_TAP
                localparam int NC = T - t;                // coefficients left on the bus
                logic [NC*CBW-1:0]     c_in;
                logic [(NC-1)*CBW-1:0] c_out;
                if (t == 1) begin : GEN_C_FIRST
                    assign c_in = c_first;
                end else begin : GEN_C_CHAIN
                    assign c_in = GEN_TAP[t-1].c_out;
                end
                tap_real #(
                    .MULT_LATENCY(MULT_LATENCY), .COEFF_WIDTH(CBW), .COEFF_FRAC_WIDTH(CBW - 1),
                    .DELAY((1 << (PFB_SIZE - N_INPUTS)) * N_POL_BLOCKS), .DATA_WIDTH(BW),
                    .BRAM_LATENCY(BRAM_LATENCY), .N_COEFFS(NC), .PLATFORM(PLATFORM)
                ) u_tap (
                    .clk(clk), .din(t_data[t-1]), .sync(t_sync[t-1]), .coeff(c_in),
                    .dout(t_data[t]), .sync_out(t_sync[t]), .coeff_out(c_out),
                    .taps_out(prod[t]));
            end

            // the one coefficient left for the last tap
            logic [CBW-1:0] c_last;
            if (T == 2) begin : GEN_C_LAST_FIRST
                assign c_last = c_first;
            end else begin : GEN_C_LAST_CHAIN
                assign c_last = GEN_TAP[T-2].c_out;
            end

            last_tap_real #(
                .BIT_WIDTH_IN(BW), .COEFF_BIT_WIDTH(CBW), .MULT_LATENCY(MULT_LATENCY)
            ) u_last_tap (
                .clk(clk), .din(t_data[T-2]), .sync(t_sync[T-2]), .coeff(c_last),
                .tap_out(prod[T-1]), .sync_out(adder_sync));

            // ── adder tree, scale, convert ─────────────────────────────────────
            logic [ADDER_N_BITS_OUT-1:0] sum, scaled;
            logic                        sum_sync;

            adder_tree #(
                .N_INPUTS(T), .DATA_WIDTH(PW), .BIN_PT(PW - 2), .TYPE(1), .LATENCY(ADD_LATENCY),
                .PRECISION(1), .N_BITS_OUT(ADDER_N_BITS_OUT), .BIN_PT_OUT(ADDER_BIN_PT_OUT),
                .QUANTIZATION(0), .OVERFLOW(0), .FIRST_STAGE_HDL(ADDER_FOLDING), .ADDER_IMP(ADDER_IMP)
            ) u_adder (
                .clk(clk), .sync(adder_sync), .din(prod), .sync_out(sum_sync), .dout(sum));

            // Scale: the value times 2^SCALE_FACTOR, the bits unchanged
            scale #(
                .N_BITS_IN(ADDER_N_BITS_OUT), .BIN_PT_IN(ADDER_BIN_PT_OUT), .TYPE_IN(1),
                .SCALE_FACTOR(SCALE_FACTOR),
                .N_BITS_OUT(ADDER_N_BITS_OUT), .BIN_PT_OUT(ADDER_BIN_PT_OUT - SCALE_FACTOR),
                .TYPE_OUT(1), .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(0)
            ) u_scale (.clk(clk), .din(sum), .dout(scaled));

            convert #(
                .N_BITS_IN(ADDER_N_BITS_OUT), .BIN_PT_IN(ADDER_BIN_PT_OUT - SCALE_FACTOR), .TYPE_IN(1),
                .N_BITS_OUT(N_BITS_OUT), .BIN_PT_OUT(N_BITS_OUT - 1), .TYPE_OUT(1),
                .QUANTIZATION(OUT_QUANT), .OVERFLOW(0), .LATENCY(CONV_LATENCY)
            ) u_convert (.clk(clk), .din(scaled), .dout(dout[K]));

            if (p == 0 && n == 0) begin : GEN_SYNC_OUT
                pipeline #(.BITWIDTH(1), .LATENCY(CONV_LATENCY)) u_delay1 (
                    .clk(clk), .din(sum_sync), .dout(sync_out));
            end
        end
    end

endmodule
