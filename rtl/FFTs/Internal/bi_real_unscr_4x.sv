// bi_real_unscr_4x — unscramble a biplex FFT of four real signals
//
// Corresponds to casper_library's bi_real_unscr_4x (fixed point, sync mode,
// bi_real_unscr_4x_init.m), the back end of fft_biplex_real_4x. biplex_core
// gets z1 = pol1 + j·pol2 and z2 = pol3 + j·pol4 and outputs, per frame of
// N = 2^FFT_SIZE cycles, z1 in the first half and z2 in the second, `even`
// carrying bins bit_rev(k) and `odd` bins bit_rev(k) + N/2 (k = 0 … N/2-1).
// This block turns that into the full N-bin spectra of the four real
// signals, one bin per cycle, all four in parallel (pol1_out … pol4_out).
// With HALF = N/2:
//
//   reorder_even (map bit_rev(k))        ─► Z[k]
//   reorder_odd  (map bit_rev(HALF-1-k)) ─► delay 1 ─► Z[N-k]
//   count = FFT_SIZE-bit counter cleared by reorder_even's sync_out
//   r0 = (count == HALF), r1 = (count == 0)            (Relational a=b)
//   mux0 = r0 ? odd : even    mux1 = r1 ? even : odd    (Mux, latency 1)
//   mux2 = r1 ? odd : even    mux3 = r0 ? even : odd
//   hilbert0(mux0, mux1), hilbert1(mux2, mux3)
//   hilbert0 outputs ─► delay HALF ─┬► mirror_spectrum din0 / din1
//   hilbert1 outputs ───────────────┼► mirror_spectrum din2 / din3
//                                   └► reorder_out (map HALF-1-k, 4 streams)
//                                        ─► delay 1 ─► mirror_spectrum reo_in0..3
//   sync: reorder_even sync_out ─► delay ADD+CONV+1 ─► delay HALF ─► mirror_spectrum
//
// (r0 / r1 handle bins 0 and N/2, where Z[N-k] would come from the other
// half-frame.) The reorders use MAP_LATENCY = 3 if BRAM_MAP else 1 and
// FANOUT_LATENCY = max(0, FFT_SIZE + ceil(log2(N_BITS·N_INPUTS·2)) - 15); the
// HALF delays are delay_bram if BRAM_DELAYS or HALF > 52, else delay_srl, and
// the sync's HALF delay is sync_delay if HALF > 52, else delay_srl, as in
// casper. mirror_spectrum gets BRAM_LATENCY + MAP_LATENCY + 2 +
// FANOUT_LATENCY as its bram_latency and negate latency 0.
//
// The reorders read their maps from MAP_DIR + "map_even.mem", "map_odd.mem"
// and "map_out.mem"; generate them with rtl/Reorder/scripts/gen_reorder_map.py
// --bi-real {even,odd,out} --fft-size FFT_SIZE. The reorders need a sync every
// N cycles (one per frame), as biplex_core provides.
//
// Complex lanes are packed {im, re} per lane, lane 0 lowest, inside the
// reorders. Declared for traceability only: DSP48_ADDERS (ignored).
//
// ASYNC = 1 (bi_real_unscr_4x_init.m:140-650): en drives the reorder_even /
// reorder_odd en; reorder_even valid enables count (rst = its sync_out AND
// valid) and, delayed 1, rides the hilberts' misc path; reorder_odd valid
// gates d0. The hilbert outputs and misco get one fan-out register each
// (dd*, den*); den gates the HALF delays and the sync delay (delay_srl /
// delay_bram / sync_delay_en with en), the sync is ANDed with den (l1), den
// is the reorder_out and mirror_spectrum en, reorder_out valid gates
// d3..d6, and dvalid = mirror_spectrum dvalid. d2 is one cycle longer, so
// the block has one more cycle of latency than with ASYNC = 0.
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
// block = 'casper_library_ffts_internal.slx/bi_real_unscr_4x'
// deviations = [
//   'dsp48_adders is a dead parameter in both models: bi_real_unscr_4x_init.m:90 reads it but never uses it, and the HDL ignores DSP48_ADDERS',
//   'FFTSize=2 reproduces an upstream casper_library defect bit-exactly: map_even = bit_rev over FFTSize-1 = 1 bit is the identity (reorder order 1, one cycle faster than the order-2 map_odd), so both Simulink and the HDL output a wrong spectrum; only FFT_SIZE >= 3 gives a correct FFT (mlib_devel_notes/fft_wideband_real_hdl_plan.md Phase 5)',
//   'the reorder maps are not computed in the HDL: MAP_DIR must hold map_even/map_odd/map_out.mem from rtl/Reorder/scripts/gen_reorder_map.py --bi-real; a missing or stale map silently changes the output order',
//   'test vectors in casper_dsp/test_data/FFTs/Internal/bi_real_unscr_4x/test_data.md come from a Python reference model (not exported from MATLAB), so cycle/bit equivalence with the Simulink block is unverified',
// ]
//
// [params.BRAM_MAP]
// mask = 'bram_map'
// type = 'checkbox'
// [params.BRAM_MAP.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.BRAM_DELAYS]
// mask = 'bram_delays'
// type = 'checkbox'
// [params.BRAM_DELAYS.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.DSP48_ADDERS]
// mask = 'dsp48_adders'
// type = 'checkbox'
// note = 'declared only; also unused by bi_real_unscr_4x_init.m (read at line 90, never referenced)'
// [params.DSP48_ADDERS.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// note = 'async = on: reorders, d0/d3..d6, count and the HALF / sync delays operate on valid samples, the arithmetic is free, dvalid = mirror_spectrum dvalid; one more cycle of latency than async = off (d2 and the dd/den fan-out registers, bi_real_unscr_4x_init.m:335-343, 461-504). The HDL ports always exist, dvalid = 0 when ASYNC = 0'
// [params.ASYNC.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.FFT_SIZE]
// mask = 'FFTSize'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [mask_set.floating_point]
// value = 'off'
//
// [[unsupported]]
// when = 'ASYNC != 0 && BRAM_DELAYS != 0 && BRAM_LATENCY == 1'
// reason = 'mlib_devel bug 14 (docs/bugs.md): with bram_delays on, bi_real_unscr_4x_init.m:508-520 passes bram_latency to the async delay_bram half-frame delays, and delay_bram_init.m:131-157 creates no dout for bram_latency = 1 (from source; delay_bram confirmed in MATLAB R2021a)'
//
// [hdl_only]
// MAP_DIR = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// float_type = 'floating point is not implemented'
// exp_width = 'floating point is not implemented'
// frac_width = 'floating point is not implemented'
//
// [ports]
// note = 'each Simulink complex port x is split into x_re / x_im'
// order = 'async only: en is input 4 and dvalid output 6 (bi_real_unscr_4x_init.m:140-162)'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module bi_real_unscr_4x #(
    parameter int    N_INPUTS     = 1,
    parameter int    FFT_SIZE     = 3,
    parameter int    N_BITS       = 18,
    parameter int    BIN_PT       = 17,
    parameter int    ADD_LATENCY  = 1,
    parameter int    CONV_LATENCY = 1,
    parameter int    BRAM_LATENCY = 2,
    parameter int    BRAM_MAP     = 0,
    parameter int    BRAM_DELAYS  = 0,
    parameter string MAP_DIR      = "",
    parameter string PLATFORM     = "GENERIC",
    // declared, not implemented (see header)
    parameter int    DSP48_ADDERS = 0,
    parameter int    ASYNC        = 0      // casper async: 1 = en / dvalid (see header)
)(
    input  logic              clk,
    input  logic              sync,
    input  logic [N_BITS-1:0] even_re     [N_INPUTS],
    input  logic [N_BITS-1:0] even_im     [N_INPUTS],
    input  logic [N_BITS-1:0] odd_re      [N_INPUTS],
    input  logic [N_BITS-1:0] odd_im      [N_INPUTS],
    input  logic              en = 1'b1,
    output logic              sync_out,
    output logic [N_BITS-1:0] pol1_out_re [N_INPUTS],
    output logic [N_BITS-1:0] pol1_out_im [N_INPUTS],
    output logic [N_BITS-1:0] pol2_out_re [N_INPUTS],
    output logic [N_BITS-1:0] pol2_out_im [N_INPUTS],
    output logic [N_BITS-1:0] pol3_out_re [N_INPUTS],
    output logic [N_BITS-1:0] pol3_out_im [N_INPUTS],
    output logic [N_BITS-1:0] pol4_out_re [N_INPUTS],
    output logic [N_BITS-1:0] pol4_out_im [N_INPUTS],
    output logic              dvalid
);

    localparam int B           = N_BITS;
    localparam int W           = 2 * B * N_INPUTS;
    localparam int HALF        = 1 << (FFT_SIZE - 1);
    localparam int MAP_LATENCY = (BRAM_MAP != 0) ? 3 : 1;
    localparam int FANOUT_RAW  = FFT_SIZE + $clog2(W) - 15;
    localparam int FANOUT      = (FANOUT_RAW > 0) ? FANOUT_RAW : 0;
    localparam int MS_BRAM     = BRAM_LATENCY + MAP_LATENCY + 2 + FANOUT;
    // bit_rev over FFT_SIZE-1 bits is the identity for FFT_SIZE = 2
    localparam int ORDER_EVEN  = (FFT_SIZE == 2) ? 1 : 2;

    localparam int AS          = (ASYNC != 0) ? 1 : 0;   // extra async fan-out latency
    if (FFT_SIZE < 2) $fatal(1, "bi_real_unscr_4x: FFT_SIZE must be >= 2");

    // ── pack / unpack complex lanes ──────────────────────────────────────────
    function automatic logic [W-1:0] pack(input logic [B-1:0] re [N_INPUTS],
                                          input logic [B-1:0] im [N_INPUTS]);
        logic [W-1:0] w;
        for (int n = 0; n < N_INPUTS; n++) begin
            w[2*n*B +: B]     = re[n];
            w[(2*n+1)*B +: B] = im[n];
        end
        return w;
    endfunction

    logic [W-1:0] even_w, odd_w;
    assign even_w = pack(even_re, even_im);
    assign odd_w  = pack(odd_re, odd_im);

    // ── reorder even / odd ───────────────────────────────────────────────────
    logic [W-1:0] reo_e [1], reo_o [1], odd_d, mux [4];
    logic         reo_sync, val_e, val_o;

    reorder #(
        .N_INPUTS(1), .N_BITS(W), .MAP_LEN(HALF), .ORDER(ORDER_EVEN),
        .MAP_INIT_FILE({MAP_DIR, "map_even.mem"}), .MAP_LATENCY(MAP_LATENCY),
        .BRAM_LATENCY(BRAM_LATENCY), .FANOUT_LATENCY(FANOUT), .BRAM_MAP(BRAM_MAP),
        .PLATFORM(PLATFORM)
    ) u_reorder_even (.clk(clk), .sync(sync), .en((AS != 0) ? en : 1'b1), .din('{even_w}),
                      .sync_out(reo_sync), .valid(val_e), .dout(reo_e));

    reorder #(
        .N_INPUTS(1), .N_BITS(W), .MAP_LEN(HALF), .ORDER(2),
        .MAP_INIT_FILE({MAP_DIR, "map_odd.mem"}), .MAP_LATENCY(MAP_LATENCY),
        .BRAM_LATENCY(BRAM_LATENCY), .FANOUT_LATENCY(FANOUT), .BRAM_MAP(BRAM_MAP),
        .PLATFORM(PLATFORM)
    ) u_reorder_odd (.clk(clk), .sync(sync), .en((AS != 0) ? en : 1'b1), .din('{odd_w}),
                     .sync_out(), .valid(val_o), .dout(reo_o));

    // d0: en = reorder_odd valid (async)
    delay_srl #(.BITWIDTH(W), .DELAY_LEN(1), .USE_ENABLE(1), .USE_RST(0)) u_d0 (
        .clk(clk), .rst(1'b0), .en((AS != 0) ? val_o : 1'b1), .din(reo_o[0]), .dout(odd_d));

    // ── bin 0 / bin N/2 selects ──────────────────────────────────────────────
    logic [FFT_SIZE-1:0] count;
    logic                r0, r1;

    // async: rst = l0 = reorder_even sync AND valid, en = reorder_even valid
    counter #(
        .COUNTER_TYPE(0), .NBITS(FFT_SIZE), .COUNT_DIR(0), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(AS)
    ) u_count (.clk(clk), .rst((AS != 0) ? reo_sync & val_e : reo_sync),
               .enable((AS != 0) ? val_e : 1'b1), .dout(count));

    relational #(.NBITS(FFT_SIZE), .COMP(0), .LATENCY(0)) u_r0 (
        .clk(clk), .a(FFT_SIZE'(HALF)), .b(count), .out(r0));
    relational #(.NBITS(FFT_SIZE), .COMP(0), .LATENCY(0)) u_r1 (
        .clk(clk), .a(count), .b(FFT_SIZE'(0)), .out(r1));

    // casper Mux: input 2 = d0 (sel 0), input 3 = d1 (sel 1)
    multiplexer #(.NBITS(W), .NINPUTS(2), .LATENCY(1)) u_mux0 (
        .clk(clk), .din('{reo_e[0], odd_d}), .sel(r0), .dout(mux[0]));
    multiplexer #(.NBITS(W), .NINPUTS(2), .LATENCY(1)) u_mux1 (
        .clk(clk), .din('{odd_d, reo_e[0]}), .sel(r1), .dout(mux[1]));
    multiplexer #(.NBITS(W), .NINPUTS(2), .LATENCY(1)) u_mux2 (
        .clk(clk), .din('{reo_e[0], odd_d}), .sel(r1), .dout(mux[2]));
    multiplexer #(.NBITS(W), .NINPUTS(2), .LATENCY(1)) u_mux3 (
        .clk(clk), .din('{odd_d, reo_e[0]}), .sel(r0), .dout(mux[3]));

    // ── hilbert ──────────────────────────────────────────────────────────────
    // h_re[h][o][n]: hilbert h, output o (0 = even, 1 = odd), lane n
    logic [B-1:0] m_re [4][N_INPUTS], m_im [4][N_INPUTS];
    logic [B-1:0] h_re [2][2][N_INPUTS], h_im [2][2][N_INPUTS];
    logic         d1, h_misc [2], den;

    // d1: reorder_even valid delayed 1, the hilberts' misci (async)
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(1)) u_d1 (.clk(clk), .din(val_e), .dout(d1));

    for (genvar i = 0; i < 4; i++) begin : GEN_UNPACK
        for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
            assign m_re[i][n] = mux[i][2*n*B +: B];
            assign m_im[i][n] = mux[i][(2*n+1)*B +: B];
        end
    end

    for (genvar h = 0; h < 2; h++) begin : GEN_HILBERT
        logic [B-1:0] e_re [N_INPUTS], e_im [N_INPUTS], o_re_h [N_INPUTS], o_im_h [N_INPUTS];
        hilbert #(
            .N_INPUTS(N_INPUTS), .BIT_WIDTH(B), .BIN_PT_IN(BIN_PT),
            .ADD_LATENCY(ADD_LATENCY), .CONV_LATENCY(CONV_LATENCY), .MISC(AS)
        ) u_hilbert (
            .clk(clk),
            .a_re(m_re[2*h]), .a_im(m_im[2*h]), .b_re(m_re[2*h+1]), .b_im(m_im[2*h+1]),
            .misci(d1),
            .even_re(e_re), .even_im(e_im), .odd_re(o_re_h), .odd_im(o_im_h), .misco(h_misc[h]));
        // dd*: one fan-out register per hilbert output (async only)
        for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_DD
            pipeline #(.BITWIDTH(4 * B), .CSP_LATENCY(AS)) u_dd (
                .clk(clk), .din({e_re[n], e_im[n], o_re_h[n], o_im_h[n]}),
                .dout({h_re[h][0][n], h_im[h][0][n], h_re[h][1][n], h_im[h][1][n]}));
        end
    end

    // den0..den5: hilbert misco (the en) delayed 1; all equal
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(1)) u_den (.clk(clk), .din(h_misc[0]), .dout(den));
    wire den_en = (AS != 0) ? den : 1'b1;

    // ── half-frame delays of hilbert0 and of the sync ───────────────────────
    logic [W-1:0] h0_w [2], dly_w [2], ch_w [4];
    logic         sync_d2, ms_sync;

    for (genvar o = 0; o < 2; o++) begin : GEN_DELAY
        assign h0_w[o] = pack(h_re[0][o], h_im[0][o]);
        // casper passes bram_latency only with bram_delays on (else the
        // delay_bram mask default, 2)
        if (BRAM_DELAYS != 0 || HALF > 52) begin : GEN_BRAM
            delay_bram #(.BITWIDTH(W), .DELAY_LEN(HALF), .BRAM_LATENCY((BRAM_DELAYS != 0) ? BRAM_LATENCY : 2),
                         .ASYNC(AS), .PLATFORM(PLATFORM)) u_delay (
                .clk(clk), .din(h0_w[o]), .en(den_en), .dout(dly_w[o]));
        end else begin : GEN_SRL
            delay_srl #(.BITWIDTH(W), .DELAY_LEN(HALF), .USE_ENABLE(1), .USE_RST(0)) u_delay (
                .clk(clk), .rst(1'b0), .en(den_en), .din(h0_w[o]), .dout(dly_w[o]));
        end
    end

    // d2: add+conv+1, one more in async
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(ADD_LATENCY + CONV_LATENCY + 1 + AS)) u_d2 (
        .clk(clk), .din(reo_sync), .dout(sync_d2));

    logic sync_dl;
    if (HALF > 52 && AS == 0) begin : GEN_SYNC_DELAY
        sync_delay #(.DELAY_LEN(HALF)) u_sync_delay (.clk(clk), .din(sync_d2), .dout(sync_dl));
    end else if (HALF > 52) begin : GEN_SYNC_DELAY_EN
        // casper sync_delay_en (DelayLen HALF, en = den): a down counter loaded
        // by the sync whatever en, decremented on en; out = (count == 1)
        localparam int SB = ($clog2(HALF + 1) > 2) ? $clog2(HALF + 1) : 2;
        logic [SB-1:0] scnt, scnt_next;
        always_comb begin
            if (sync_d2)                 scnt_next = SB'(HALF);
            else if (den && scnt != '0)  scnt_next = scnt - 1'b1;
            else                         scnt_next = scnt;
        end
        register #(.BITWIDTH(SB), .USE_RST(0), .USE_ENABLE(0), .INIT_VAL(0)) u_scnt (
            .clk(clk), .rst(1'b0), .en(1'b1), .d(scnt_next), .q(scnt));
        assign sync_dl = (scnt == SB'(1));
    end else begin : GEN_SYNC_SRL
        delay_srl #(.BITWIDTH(1), .DELAY_LEN(HALF), .USE_ENABLE(1), .USE_RST(0)) u_sync_delay (
            .clk(clk), .rst(1'b0), .en(den_en), .din(sync_d2), .dout(sync_dl));
    end
    // l1: sync AND den (async)
    assign ms_sync = (AS != 0) ? sync_dl & den : sync_dl;

    // channels: pol1 / pol2 = delayed hilbert0, pol3 / pol4 = hilbert1
    assign ch_w = '{dly_w[0], dly_w[1], pack(h_re[1][0], h_im[1][0]), pack(h_re[1][1], h_im[1][1])};

    // ── reorder_out and mirror_spectrum ─────────────────────────────────────
    logic [W-1:0] reo_out [4], reo_out_d [4];
    logic         val_out;
    logic [B-1:0] c_re [4][N_INPUTS], c_im [4][N_INPUTS];
    logic [B-1:0] r_re [4][N_INPUTS], r_im [4][N_INPUTS];
    logic [B-1:0] o_re [4][N_INPUTS], o_im [4][N_INPUTS];

    reorder #(
        .N_INPUTS(4), .N_BITS(W), .MAP_LEN(HALF), .ORDER(2),
        .MAP_INIT_FILE({MAP_DIR, "map_out.mem"}), .MAP_LATENCY(MAP_LATENCY),
        .BRAM_LATENCY(BRAM_LATENCY), .FANOUT_LATENCY(FANOUT), .BRAM_MAP(BRAM_MAP),
        .PLATFORM(PLATFORM)
    ) u_reorder_out (.clk(clk), .sync(ms_sync), .en(den_en), .din(ch_w), .sync_out(),
                     .valid(val_out), .dout(reo_out));

    for (genvar i = 0; i < 4; i++) begin : GEN_CH
        // d3..d6: en = reorder_out valid (async)
        delay_srl #(.BITWIDTH(W), .DELAY_LEN(1), .USE_ENABLE(1), .USE_RST(0)) u_d (
            .clk(clk), .rst(1'b0), .en((AS != 0) ? val_out : 1'b1), .din(reo_out[i]), .dout(reo_out_d[i]));
        for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
            assign c_re[i][n] = ch_w[i][2*n*B +: B];
            assign c_im[i][n] = ch_w[i][(2*n+1)*B +: B];
            assign r_re[i][n] = reo_out_d[i][2*n*B +: B];
            assign r_im[i][n] = reo_out_d[i][(2*n+1)*B +: B];
        end
    end

    mirror_spectrum #(
        .N_INPUTS(N_INPUTS), .FFT_SIZE(FFT_SIZE), .INPUT_BITWIDTH(B), .BIN_PT_IN(BIN_PT),
        .BRAM_LATENCY(MS_BRAM), .NEGATE_LATENCY(0), .NEGATE_MODE(0), .ASYNC(ASYNC)
    ) u_mirror_spectrum (
        .clk(clk), .sync(ms_sync), .en(den_en),
        .din0_re(c_re[0]), .din0_im(c_im[0]), .reo_in0_re(r_re[0]), .reo_in0_im(r_im[0]),
        .din1_re(c_re[1]), .din1_im(c_im[1]), .reo_in1_re(r_re[1]), .reo_in1_im(r_im[1]),
        .din2_re(c_re[2]), .din2_im(c_im[2]), .reo_in2_re(r_re[2]), .reo_in2_im(r_im[2]),
        .din3_re(c_re[3]), .din3_im(c_im[3]), .reo_in3_re(r_re[3]), .reo_in3_im(r_im[3]),
        .sync_out(sync_out),
        .dout0_re(o_re[0]), .dout0_im(o_im[0]), .dout1_re(o_re[1]), .dout1_im(o_im[1]),
        .dout2_re(o_re[2]), .dout2_im(o_im[2]), .dout3_re(o_re[3]), .dout3_im(o_im[3]), .dvalid(dvalid));

    assign pol1_out_re = o_re[0];  assign pol1_out_im = o_im[0];
    assign pol2_out_re = o_re[1];  assign pol2_out_im = o_im[1];
    assign pol3_out_re = o_re[2];  assign pol3_out_im = o_im[2];
    assign pol4_out_re = o_re[3];  assign pol4_out_im = o_im[3];

endmodule
