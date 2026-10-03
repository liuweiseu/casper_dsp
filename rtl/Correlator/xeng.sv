// xeng — casper_library windowed X-engine with descramble
// (casper_library_correlator.slx, Block SID 410; xeng_init.m)
//
// The library stores an empty shell (n_ants = 0 makes xeng_init.m clear the
// block), so the structure comes from xeng_init.m:
//
//   ant ─┬─ auto_tap.a_del / a_ndel        acc_in = 0, valid_in = 0, sync_in
//        │      │ 1..7 ─► baseline_tap1 ─► ... ─► baseline_tapK   (K = N_ANTS/2,
//        │      │                                   output p -> input p)
//        │      └─ a_loop ◄── baseline_tapK.a_del_out
//   window_valid ─ window_delay(XENG_DELAY) ─────────────────► descramble.win_valid
//   baseline_tapK acc_out / valid_out / sync_out ────────────► descramble acc / valid / sync
//   descramble ─► acc, valid, sync_out
//   mcnt_in ─ sample_and_hold1(sync_in) ─ sample_and_hold2(tapK.sync_out)
//           ─ sample_and_hold3(descramble.sync_out) ─ Delay(1) ─ mcnt_out
//     (all three with period N_ANTS*ACC_LEN)
//   descramble = xeng_descramble_4ant for N_ANTS = 4, xeng_descramble otherwise
//   XENG_DELAY = ADD_LATENCY + MULT_LATENCY + ACC_LEN + floor(N_ANTS/2+1) + 1
//   (equal to auto_tap's sync delay S)
//
// With the loop closed, auto_tap.a_end_out lags ant by exactly
// N_ANTS*ACC_LEN cycles, and tap k integrates ant_j x conj(ant_(j+k) mod N).
// The taps' dumps reach the end of the relay chain as one burst of T = K+1
// words per antenna line (tap K first, autocorrelation last), the order the
// descramble's tap counter expects. Each descramble readout holds one
// complete set of E = N(N+1)/2 baselines of one data frame (its conjugated
// region from the next output window, see xeng_descramble).
//
// Tap output -> descramble: the taps' words are 8*N_BITS_OUT bits with
// N_BITS_OUT = 2*N_BITS + 1 + ceil(log2 ACC_LEN), the descramble slices
// W-bit fields (W = 2*N_BITS + floor(log2 ACC_LEN) + 1) at offsets k*W from
// the LSB of whatever it gets. So the connection is equivalent to passing
// the low 8*W bits. For a power-of-2 ACC_LEN, W = N_BITS_OUT and nothing is
// lost; otherwise W = N_BITS_OUT - 1 and the fields are misaligned (each
// field mixes bits of two neighbouring parts), as in the library; that case
// gets a $warning.
//
// Ports (numbering = creation order in xeng_init.m; confirmed for the
// original three of each by the older xeng in casper_library/Tests/
// xeng_test.mdl: in sync_in 1, ant 2, window_valid 3; out sync_out 1,
// acc 2, valid 3; the mcnt ports were added as 4):
//   in : sync_in, ant[4*N_BITS], window_valid, mcnt_in[MCNT_BITS]
//   out: sync_out, acc[OW], valid, mcnt_out[MCNT_BITS]
//
// Parameters (mask names; defaults = stored mask values except N_ANTS: the
// stored n_ants = 0 is the empty-shell value, so N_ANTS uses xeng_init.m's
// default 8):
//   N_ANTS 8, N_BITS 4, ACC_LEN 128, DEMUX_FACTOR 4, ADD_LATENCY 1,
//   MULT_LATENCY 1, BRAM_LATENCY 2, USE_DED_MULT 1, USE_BRAM_DELAY 1.
//   USE_DED_MULT is passed by the mask but xeng_init.m reads 'mult_type'
//   instead, which falls back to its default 1 (embedded multipliers) for
//   every tap: declared only, the taps get MULT_TYPE 1. Multiplier type and
//   USE_BRAM_DELAY are resource-only anyway.
//   MCNT_BITS (width of mcnt_in/out, inherited in Simulink) and PLATFORM
//   (RAMs) are not mask parameters.
// Checks: N_ANTS < 4 (the mask silently uses 4), N_ANTS = 5 (mask error),
// odd N_ANTS (the descramble needs even), ACC_LEN <= floor(N_ANTS/2+1)
// (mask error) are $fatal.

module xeng #(
    parameter int    N_ANTS         = 8,
    parameter int    N_BITS         = 4,
    parameter int    ACC_LEN        = 128,
    parameter int    DEMUX_FACTOR   = 4,
    parameter int    ADD_LATENCY    = 1,
    parameter int    MULT_LATENCY   = 1,
    parameter int    BRAM_LATENCY   = 2,
    parameter int    USE_DED_MULT   = 1,
    parameter int    USE_BRAM_DELAY = 1,
    parameter int    MCNT_BITS      = 32,
    parameter string PLATFORM       = "GENERIC",
    // derived; not to be overridden
    parameter int    N_BITS_OUT     = 2 * N_BITS + 1 + $clog2(ACC_LEN),
    parameter int    W              = 2 * N_BITS + $clog2(ACC_LEN + 1),
    parameter int    OW             = 8 * (1 << $clog2(W)) / DEMUX_FACTOR
)(
    input  logic                 clk,
    input  logic                 sync_in,
    input  logic [4*N_BITS-1:0]  ant,
    input  logic                 window_valid,
    input  logic [MCNT_BITS-1:0] mcnt_in,
    output logic                 sync_out,
    output logic [OW-1:0]        acc,
    output logic                 valid,
    output logic [MCNT_BITS-1:0] mcnt_out
);

    localparam int K          = N_ANTS / 2;
    localparam int M          = N_BITS_OUT;
    localparam int AW         = 4 * N_BITS;
    localparam int XENG_DELAY = ADD_LATENCY + MULT_LATENCY + ACC_LEN + (N_ANTS / 2 + 1) + 1;
    localparam int MULT_TYPE  = 1;    // xeng_init.m's mult_type default (see header)

    initial begin
        if (N_ANTS < 4)
            $fatal(1, "xeng: N_ANTS must be >= 4 (the mask replaces %0d by 4)", N_ANTS);
        if (N_ANTS == 5)
            $fatal(1, "xeng: 5 antennas are not supported (xeng_init.m: special case)");
        if (N_ANTS % 2 != 0)
            $fatal(1, "xeng: N_ANTS must be even (xeng_descramble needs it; got %0d)", N_ANTS);
        if (ACC_LEN <= N_ANTS / 2 + 1)
            $fatal(1, "xeng: ACC_LEN (%0d) must be > floor(N_ANTS/2 + 1) = %0d", ACC_LEN, N_ANTS / 2 + 1);
        if (N_BITS_OUT != 2 * N_BITS + 1 + $clog2(ACC_LEN) || W != 2 * N_BITS + $clog2(ACC_LEN + 1)
            || OW != 8 * (1 << $clog2(W)) / DEMUX_FACTOR)
            $fatal(1, "xeng: N_BITS_OUT / W / OW are derived, do not override");
        if (W != N_BITS_OUT)
            $warning("xeng: ACC_LEN %0d is not a power of 2: the descramble slices %0d-bit fields out of the %0d-bit tap outputs, its output fields are misaligned (as in the library)",
                     ACC_LEN, W, N_BITS_OUT);
    end

    // ── auto_tap ─────────────────────────────────────────────────────────────
    logic [AW-1:0]  auto_a_del, auto_a_ndel, auto_a_end, a_loop;
    logic [8*M-1:0] auto_acc;
    logic           auto_valid, auto_rst, auto_sync;

    auto_tap #(
        .N_ANTS(N_ANTS), .N_BITS(N_BITS), .ACC_LEN(ACC_LEN), .ADD_LATENCY(ADD_LATENCY),
        .MULT_LATENCY(MULT_LATENCY), .BRAM_LATENCY(BRAM_LATENCY), .MULT_TYPE(MULT_TYPE),
        .USE_BRAM_DELAY(USE_BRAM_DELAY), .PLATFORM(PLATFORM)
    ) u_auto_tap (
        .clk(clk), .a_del(ant), .a_ndel(ant), .a_loop(a_loop), .acc_in('0), .valid_in(1'b0),
        .sync_in(sync_in), .a_del_out(auto_a_del), .a_ndel_out(auto_a_ndel),
        .a_end_out(auto_a_end), .acc_out(auto_acc), .valid_out(auto_valid),
        .rst_out(auto_rst), .sync_out(auto_sync));

    // ── baseline taps 1..K (output port p -> next tap's input port p) ────────
    for (genvar i = 1; i <= K; i++) begin : GEN_TAP
        logic [AW-1:0]  a_del_i, a_ndel_i, a_end_i;
        logic [8*M-1:0] acc_i;
        logic           valid_i, rst_i, sync_i;
        logic [AW-1:0]  a_del_o, a_ndel_o, a_end_o;
        logic [8*M-1:0] acc_o;
        logic           valid_o, rst_o, sync_o;

        if (i == 1) begin : GEN_FROM_AUTO
            assign {a_del_i, a_ndel_i, a_end_i} = {auto_a_del, auto_a_ndel, auto_a_end};
            assign {acc_i, valid_i, rst_i, sync_i} = {auto_acc, auto_valid, auto_rst, auto_sync};
        end else begin : GEN_FROM_PREV
            assign {a_del_i, a_ndel_i, a_end_i} =
                {GEN_TAP[i-1].a_del_o, GEN_TAP[i-1].a_ndel_o, GEN_TAP[i-1].a_end_o};
            assign {acc_i, valid_i, rst_i, sync_i} =
                {GEN_TAP[i-1].acc_o, GEN_TAP[i-1].valid_o, GEN_TAP[i-1].rst_o, GEN_TAP[i-1].sync_o};
        end

        baseline_tap #(
            .N_ANTS(N_ANTS), .ANT_SEP(i), .N_BITS(N_BITS), .ACC_LEN(ACC_LEN),
            .ADD_LATENCY(ADD_LATENCY), .MULT_LATENCY(MULT_LATENCY), .BRAM_LATENCY(BRAM_LATENCY),
            .MULT_TYPE(MULT_TYPE), .USE_BRAM_DELAY(USE_BRAM_DELAY), .PLATFORM(PLATFORM)
        ) u_baseline_tap (
            .clk(clk), .a_del(a_del_i), .a_ndel(a_ndel_i), .a_end(a_end_i), .acc_in(acc_i),
            .valid_in(valid_i), .rst(rst_i), .sync1(sync_i), .a_del_out(a_del_o),
            .a_ndel_out(a_ndel_o), .a_end_out(a_end_o), .acc_out(acc_o), .valid_out(valid_o),
            .rst_out(rst_o), .sync_out(sync_o));
    end

    // loop back; tapK's a_ndel_out, a_end_out and rst_out are terminated
    assign a_loop = GEN_TAP[K].a_del_o;

    logic [8*M-1:0] tap_acc;
    logic           tap_valid, tap_sync;
    assign tap_acc   = GEN_TAP[K].acc_o;
    assign tap_valid = GEN_TAP[K].valid_o;
    assign tap_sync  = GEN_TAP[K].sync_o;

    // ── window_delay and descramble ──────────────────────────────────────────
    logic win_valid, desc_sync;

    window_delay #(.DELAY(XENG_DELAY)) u_window_delay (
        .clk(clk), .din(window_valid), .dout(win_valid));

    generate
        if (N_ANTS == 4) begin : GEN_DESC_4ANT
            xeng_descramble_4ant #(
                .N_BITS(N_BITS), .ACC_LEN(ACC_LEN), .DEMUX_FACTOR(DEMUX_FACTOR), .PLATFORM(PLATFORM)
            ) u_descramble (
                .clk(clk), .acc(tap_acc[8*W-1:0]), .valid(tap_valid), .sync(tap_sync),
                .win_valid(win_valid), .acc_out(acc), .valid_out(valid), .sync_out(desc_sync));
        end else begin : GEN_DESC
            xeng_descramble #(
                .NUM_ANTS(N_ANTS), .N_BITS(N_BITS), .ACC_LEN(ACC_LEN), .DEMUX_FACTOR(DEMUX_FACTOR),
                .PLATFORM(PLATFORM)
            ) u_descramble (
                .clk(clk), .acc(tap_acc[8*W-1:0]), .valid(tap_valid), .sync(tap_sync),
                .win_valid(win_valid), .acc_out(acc), .valid_out(valid), .sync_out(desc_sync));
        end
    endgenerate

    assign sync_out = desc_sync;

    // ── mcnt ─────────────────────────────────────────────────────────────────
    logic [MCNT_BITS-1:0] mcnt1, mcnt2, mcnt3;

    sample_and_hold #(.PERIOD(N_ANTS * ACC_LEN), .BITWIDTH(MCNT_BITS)) u_sample_and_hold1 (
        .clk(clk), .sync(sync_in), .din(mcnt_in), .dout(mcnt1));
    sample_and_hold #(.PERIOD(N_ANTS * ACC_LEN), .BITWIDTH(MCNT_BITS)) u_sample_and_hold2 (
        .clk(clk), .sync(tap_sync), .din(mcnt1), .dout(mcnt2));
    sample_and_hold #(.PERIOD(N_ANTS * ACC_LEN), .BITWIDTH(MCNT_BITS)) u_sample_and_hold3 (
        .clk(clk), .sync(desc_sync), .din(mcnt2), .dout(mcnt3));
    delay #(.LATENCY(1), .BITWIDTH(MCNT_BITS)) u_mcnt_delay (
        .clk(clk), .din(mcnt3), .dout(mcnt_out));

endmodule
