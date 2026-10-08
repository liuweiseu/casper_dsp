// write_ctrl — write-side controller inside casper_library's xeng_descramble
// (casper_library_correlator.slx, system_478; xeng_descramble_4ant's copy,
// system_995, replaces Counter2 by the constant 9, which is what Counter2
// gives for NUM_ANTS = 4: PIVOT = E-1 = 9). Not a library block.
//
// Input: the X-engine's relay stream, one word of 4 complex visibilities
// {c3, c2, c1, c0} (c3 in the MSBs, each {re, im} of W bits) per valid
// cycle, in the X-engine's tap order: for every antenna line, T = N/2+1 tap
// words (tap 0 = autocorrelation, tap k = baseline separation k).
//
//   rst_in   = Delay(sync, 1) | rise(window_valid)
//   valid_in = Delay(negedge_delay(window_valid, ceil(N/2)*ACC_LEN) & xeng_valid, 1)
//   rst      = Delay(rst_in, 1)        vld = Delay(valid_in, 1)
//   dat      = Delay(data_in, 2)
//   tap     : 0..T-1,  rst = rst_in, en = (tap == T-1) | valid_in
//   line    : 0..N-1,  rst = rst_in, en = (tap == T-1) & valid_in
//   element : 0..NV-1, rst = rst_in, en = valid_in
//   last  = ~Delay(tap >= (T-1) - line, 1)    (signed compare: the AddSub
//           T-1-line is full precision, i.e. signed, the tap unsigned)
//   blank = Delay(tap == 0, 1) & last
//   Counter3 : 0 .. PIVOT-1 (start 0),  rst = rst, en = vld & ~last
//   Counter2 : PIVOT .. E-1 (start PIVOT, reset and wrap to PIVOT),
//              rst = rst, en = last & ~blank & vld
//   write_addr = last ? Counter2 : Counter3
//   enable     = vld & ~blank                                  (write enable)
//   data_out   = last ? {conj c3, conj c2, conj c0, conj c1} : dat
//                (conj = W-bit Negate of the imaginary part, Wrap; note the
//                 c1/c0 swap)
//   start_readout = rise(Delay(element == K_START, 1)), K_START = ceil(3*NV/4)
//
// The tap counter's enable is an OR: when the tap counter sits at T-1 it
// wraps on the next cycle even without a valid word (as in the diagram).
// The address map: "last triangle" words (line + tap < T-1) of taps > 0 are
// conjugated and written from PIVOT up; tap 0 of those lines (the N/2
// redundant autocorrelation slots) is blanked; all others are written from
// 0 up in arrival order.
//
// Parameters are the xeng_descramble mask initialization values (see
// xeng_descramble.sv). Unused diagram logic (pos_cnt, Gateway Outs, scope)
// is not implemented.
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
// block = 'casper_library_correlator.slx/xeng_descramble/write_ctrl'
// deviations = []
//
// [hdl_only]
// NUM_ANTS = 'xeng_descramble mask num_ants'
// ACC_LEN = 'xeng_descramble mask acc_len'
// W = 'xeng_descramble mask-init n_bits_xeng_out'
// T = 'mask-init num_taps (derived)'
// NV = 'mask-init num_validins (derived)'
// E = 'mask-init num_elements (derived)'
// PIVOT = 'mask-init pivot_pnt (derived)'
// WA_BITS = 'ceil(log2(num_elements)) (derived)'
// K_START = 'ceil(num_validins*3/4) (derived)'
// PULSE_LEN = 'ceil(num_ants/2)*acc_len (derived)'
//
// [mask_missing]
//
// [ports]
// note = 'unmasked subsystem (system_478.xml); the xeng_descramble_4ant copy (system_995.xml) replaces Counter2 by the constant 9 = PIVOT = E-1, functionally identical'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module write_ctrl #(
    parameter int NUM_ANTS  = 8,
    parameter int ACC_LEN   = 128,
    parameter int W         = 16,     // n_bits_xeng_out
    parameter int T         = NUM_ANTS / 2 + 1,
    parameter int NV        = NUM_ANTS * T,
    parameter int E         = NUM_ANTS * (NUM_ANTS + 1) / 2,
    parameter int PIVOT     = (NUM_ANTS / 2) * T + T * NUM_ANTS / 4,
    parameter int WA_BITS   = $clog2(E),
    parameter int K_START   = (3 * NV + 3) / 4,
    parameter int PULSE_LEN = ((NUM_ANTS + 1) / 2) * ACC_LEN
)(
    input  logic               clk,
    input  logic               sync,
    input  logic [8*W-1:0]     data_in,
    input  logic               xeng_valid,
    input  logic               window_valid,
    output logic               start_readout,
    output logic [WA_BITS-1:0] write_addr,
    output logic [8*W-1:0]     data_out,
    output logic               enable
);

    localparam int TAPS_BITS = $clog2(T + 1);       // floor(log2(num_taps)) + 1
    localparam int ANT_BITS  = $clog2(NUM_ANTS);    // ceil(log2(num_ants))
    localparam int VI_BITS   = $clog2(NV + 1);      // floor(log2(num_validins)) + 1
    // signed compare width: T-1-line ranges over [T-NUM_ANTS, T-1]
    localparam int CW = ((TAPS_BITS > ANT_BITS) ? TAPS_BITS : ANT_BITS) + 2;

    // ── input conditioning ───────────────────────────────────────────────────
    logic sync_d, win_rise, rst_in, win_ext, valid_in, rst, vld;
    logic [8*W-1:0] dat;

    delay #(.LATENCY(1), .BITWIDTH(1)) u_sync_d (.clk(clk), .din(sync), .dout(sync_d));
    edge_detect #(.EDGE(0), .POLARITY(0)) u_posedge (
        .clk(clk), .din(window_valid), .dout(win_rise));
    assign rst_in = sync_d | win_rise;

    negedge_delay #(.PULSE_LEN(PULSE_LEN)) u_negedge_delay (
        .clk(clk), .din(window_valid), .dout(win_ext));
    delay #(.LATENCY(1), .BITWIDTH(1)) u_valid_in (
        .clk(clk), .din(win_ext & xeng_valid), .dout(valid_in));

    delay #(.LATENCY(1), .BITWIDTH(1)) u_rst (.clk(clk), .din(rst_in), .dout(rst));
    delay #(.LATENCY(1), .BITWIDTH(1)) u_vld (.clk(clk), .din(valid_in), .dout(vld));
    delay #(.LATENCY(2), .BITWIDTH(8 * W)) u_dat (.clk(clk), .din(data_in), .dout(dat));

    // ── tap / line / element counters ────────────────────────────────────────
    logic [TAPS_BITS-1:0] tap, tap_max;
    logic [ANT_BITS-1:0]  line;
    logic [VI_BITS-1:0]   element, k_start;
    logic                 tap_end;

    constant #(.NBITS(TAPS_BITS), .VAL(T - 1)) u_tap_max (.out(tap_max));
    relational #(.NBITS(TAPS_BITS), .COMP(0), .LATENCY(0), .SIGNED(0)) u_tap_end (
        .clk(clk), .a(tap_max), .b(tap), .out(tap_end));

    counter #(
        .COUNTER_TYPE(1), .NBITS(TAPS_BITS), .COUNT_TO_VAL(T - 1), .COUNT_DIR(0), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_tap (.clk(clk), .rst(rst_in), .enable(tap_end | valid_in), .dout(tap));

    counter #(
        .COUNTER_TYPE(1), .NBITS(ANT_BITS), .COUNT_TO_VAL(NUM_ANTS - 1), .COUNT_DIR(0),
        .INIT_VAL(0), .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_line (.clk(clk), .rst(rst_in), .enable(tap_end & valid_in), .dout(line));

    counter #(
        .COUNTER_TYPE(1), .NBITS(VI_BITS), .COUNT_TO_VAL(NV - 1), .COUNT_DIR(0), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_element (.clk(clk), .rst(rst_in), .enable(valid_in), .dout(element));

    // ── last triangle / blank ────────────────────────────────────────────────
    logic [CW-1:0] tap_x, lim;
    logic          ge, last, tap0_d, blank;

    assign tap_x = CW'(tap);                         // unsigned tap, zero-extended
    assign lim   = CW'(T - 1) - CW'(line);           // AddSub T-1-line, signed
    relational #(.NBITS(CW), .COMP(5), .LATENCY(1), .SIGNED(1)) u_ge (
        .clk(clk), .a(tap_x), .b(lim), .out(ge));
    assign last = ~ge;

    logic [TAPS_BITS-1:0] zero_t;
    constant #(.NBITS(TAPS_BITS), .VAL(0)) u_zero_t (.out(zero_t));
    relational #(.NBITS(TAPS_BITS), .COMP(0), .LATENCY(1), .SIGNED(0)) u_tap0 (
        .clk(clk), .a(zero_t), .b(tap), .out(tap0_d));
    assign blank = tap0_d & last;

    // ── write address ────────────────────────────────────────────────────────
    logic [WA_BITS-1:0] c3_addr, c2_addr;

    counter #(
        .COUNTER_TYPE(1), .NBITS(WA_BITS), .COUNT_TO_VAL(PIVOT - 1), .COUNT_DIR(0), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_counter3 (.clk(clk), .rst(rst), .enable(vld & ~last), .dout(c3_addr));

    counter #(
        .COUNTER_TYPE(1), .NBITS(WA_BITS), .COUNT_TO_VAL(E - 1), .COUNT_DIR(0), .INIT_VAL(PIVOT),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(PIVOT)
    ) u_counter2 (.clk(clk), .rst(rst), .enable(last & ~blank & vld), .dout(c2_addr));

    logic [WA_BITS-1:0] addr_in [2];
    assign addr_in[0] = c3_addr;
    assign addr_in[1] = c2_addr;
    multiplexer #(.NBITS(WA_BITS), .NINPUTS(2), .LATENCY(0)) u_addr_mux (
        .clk(clk), .din(addr_in), .sel(last), .dout(write_addr));

    assign enable = vld & ~blank;

    // ── conjugated words: {conj c3, conj c2, conj c0, conj c1} ───────────────
    logic [2*W-1:0] cpx  [4];      // cpx[i] = c_i = {re, im}
    logic [2*W-1:0] conj [4];
    for (genvar i = 0; i < 4; i++) begin : GEN_CONJ
        logic [W-1:0] im_neg;
        assign cpx[i] = dat[2*W*i +: 2*W];
        negate #(
            .N_BITS_IN(W), .BIN_PT_IN(0), .TYPE_IN(1), .N_BITS_OUT(W), .BIN_PT_OUT(0),
            .TYPE_OUT(1), .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(0)
        ) u_neg (.clk(clk), .din(cpx[i][W-1:0]), .dout(im_neg));
        assign conj[i] = {cpx[i][2*W-1:W], im_neg};
    end

    logic [8*W-1:0] data_in_sel [2];
    assign data_in_sel[0] = dat;
    assign data_in_sel[1] = {conj[3], conj[2], conj[0], conj[1]};
    multiplexer #(.NBITS(8 * W), .NINPUTS(2), .LATENCY(0)) u_sel_conj (
        .clk(clk), .din(data_in_sel), .sel(last), .dout(data_out));

    // ── start of readout ─────────────────────────────────────────────────────
    logic at_k;
    constant #(.NBITS(VI_BITS), .VAL(K_START)) u_k_start (.out(k_start));
    relational #(.NBITS(VI_BITS), .COMP(0), .LATENCY(1), .SIGNED(0)) u_at_k (
        .clk(clk), .a(element), .b(k_start), .out(at_k));
    edge_detect #(.EDGE(0), .POLARITY(0)) u_posedge1 (
        .clk(clk), .din(at_k), .dout(start_readout));

endmodule
