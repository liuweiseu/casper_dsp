// fft_unscrambler — reorder the outputs of fft_direct into natural order
//
// Corresponds to casper_library's fft_unscrambler (fixed point, sync mode,
// fft_unscrambler_init.m), as fft_wideband_real uses it. There are
// G = 2^LOG2_N_GROUPS input groups, each carrying N_STREAMS complex signals.
// As casper builds it:
//
//   each group's N_STREAMS signals ─► one word (bus_create)
//   G words ─► square_transposer (LOG2_N_LANES = LOG2_N_GROUPS)
//           ─► reorder (G streams, MAP_LEN = 2^(FFT_SIZE-LOG2_N_GROUPS))
//           ─► split back into N_STREAMS signals per group (bus_expand)
//   sync ─► square_transposer ─► reorder ─► sync_out
//
// The map is part = [0 : 2^(FFT_SIZE-2·LOG2_N_GROUPS)-1]·G,
// map = [part+0, part+1, …, part+G-1]; that is, map[k] rotates the
// (FFT_SIZE-LOG2_N_GROUPS)-bit index k left by LOG2_N_GROUPS bits, so its
// order is m / gcd(m, LOG2_N_GROUPS), m = FFT_SIZE-LOG2_N_GROUPS (computed
// here; it often exceeds 2). Generate MAP_INIT_FILE with
// rtl/Reorder/scripts/gen_reorder_map.py --unscrambler --fft-size FFT_SIZE
// --log2-n-groups LOG2_N_GROUPS.
//
// Derived as fft_unscrambler_init.m does:
//   bram_map / map_latency: if 2^(FFT_SIZE-1)·(FFT_SIZE-1) >= 2^COEFFS_BIT_LIMIT
//                           and 2^(FFT_SIZE-1) >= BRAM_LATENCY:
//                           BRAM map, latency 3 if FFT_SIZE-1 > 11 else 2;
//                           otherwise latency 1
//   fanout_latency = max(0, (FFT_SIZE-LOG2_N_GROUPS)
//                    + ceil(log2(N_BITS_IN·LOG2_N_GROUPS·2)) - 15 + 2)
//                    (casper uses n_inputs = LOG2_N_GROUPS here, not 2^n_inputs)
//
// Port element k of din / dout is casper's in<s><g> / out<s><g> with
// k = s·G + g (stream s, group g), the casper port order. The reorder needs
// a sync every ORDER·2^(FFT_SIZE-LOG2_N_GROUPS) cycles (or a multiple).
//
// Requires 1 <= LOG2_N_GROUPS < FFT_SIZE-2 (casper errors for
// n_inputs >= FFTSize-2, and its square_transposer is empty for n_inputs = 0)
// and 2·LOG2_N_GROUPS <= FFT_SIZE (otherwise casper's part, and so its map,
// is empty).
// ASYNC is declared for traceability; must be 0.

module fft_unscrambler #(
    parameter int    N_STREAMS        = 2,
    parameter int    FFT_SIZE         = 15,
    parameter int    LOG2_N_GROUPS    = 2,
    parameter int    N_BITS_IN        = 18,
    parameter int    BRAM_LATENCY     = 2,
    parameter int    COEFFS_BIT_LIMIT = 8,
    parameter string MAP_INIT_FILE    = "",
    parameter string PLATFORM         = "GENERIC",
    parameter int    ASYNC            = 0
)(
    input  logic                 clk,
    input  logic                 sync,
    input  logic [N_BITS_IN-1:0] din_re  [N_STREAMS << LOG2_N_GROUPS],
    input  logic [N_BITS_IN-1:0] din_im  [N_STREAMS << LOG2_N_GROUPS],
    output logic                 sync_out,
    output logic [N_BITS_IN-1:0] dout_re [N_STREAMS << LOG2_N_GROUPS],
    output logic [N_BITS_IN-1:0] dout_im [N_STREAMS << LOG2_N_GROUPS]
);

    localparam int G       = 1 << LOG2_N_GROUPS;
    localparam int B       = N_BITS_IN;
    localparam int WG      = 2 * B * N_STREAMS;            // one group's word
    localparam int M       = FFT_SIZE - LOG2_N_GROUPS;     // map index bits
    localparam int MAP_LEN = 1 << M;

    function automatic int gcd(input int a, input int b);
        while (b != 0) begin
            int t = a % b;
            a = b;
            b = t;
        end
        return a;
    endfunction

    localparam int ORDER       = M / gcd(M, LOG2_N_GROUPS);
    localparam longint HALF_L    = longint'(1) << (FFT_SIZE - 1);
    localparam longint COEFF_LIM = longint'(1) << COEFFS_BIT_LIMIT;
    localparam longint STAGES    = longint'(FFT_SIZE) - 1;
    localparam longint BRAM_LAT  = longint'(BRAM_LATENCY);
    localparam int BRAM_MAP    = (HALF_L * STAGES >= COEFF_LIM && HALF_L >= BRAM_LAT) ? 1 : 0;
    localparam int MAP_LATENCY = (BRAM_MAP == 0) ? 1 : (FFT_SIZE - 1 > 11) ? 3 : 2;
    localparam int FANOUT_RAW  = M + $clog2(B * LOG2_N_GROUPS * 2) - 15 + 2;
    localparam int FANOUT      = (FANOUT_RAW > 0) ? FANOUT_RAW : 0;

    if (ASYNC != 0) $fatal(1, "fft_unscrambler: ASYNC is not implemented");
    if (LOG2_N_GROUPS < 1 || LOG2_N_GROUPS >= FFT_SIZE - 2 || 2 * LOG2_N_GROUPS > FFT_SIZE)
        $fatal(1, "fft_unscrambler: requires 1 <= LOG2_N_GROUPS < FFT_SIZE-2 and 2*LOG2_N_GROUPS <= FFT_SIZE");

    // ── group words: stream s of group g at bits [2·s·B +: 2·B] = {im, re} ──
    logic [WG-1:0] grp [G], trans [G], reo [G];
    logic          trans_sync;

    for (genvar g = 0; g < G; g++) begin : GEN_GROUP
        for (genvar s = 0; s < N_STREAMS; s++) begin : GEN_STREAM
            assign grp[g][2*s*B +: B]       = din_re[s*G + g];
            assign grp[g][(2*s+1)*B +: B]   = din_im[s*G + g];
            assign dout_re[s*G + g]         = reo[g][2*s*B +: B];
            assign dout_im[s*G + g]         = reo[g][(2*s+1)*B +: B];
        end
    end

    square_transposer #(.LOG2_N_LANES(LOG2_N_GROUPS), .DATA_WIDTH(WG)) u_square_transposer (
        .clk(clk), .sync(sync), .din(grp), .sync_out(trans_sync), .dout(trans));

    reorder #(
        .N_STREAMS(G), .DATA_WIDTH(WG), .MAP_LEN(MAP_LEN), .ORDER(ORDER),
        .MAP_INIT_FILE(MAP_INIT_FILE), .MAP_LATENCY(MAP_LATENCY),
        .BRAM_LATENCY(BRAM_LATENCY), .FANOUT_LATENCY(FANOUT), .BRAM_MAP(BRAM_MAP),
        .PLATFORM(PLATFORM)
    ) u_reorder (.clk(clk), .sync(trans_sync), .din(trans), .sync_out(sync_out),
                 .valid(), .dout(reo));

endmodule
