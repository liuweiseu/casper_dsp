// cmac — casper_library complex multiply-accumulate (casper_library_correlator
// .slx, Block SID 810; no _init.m, the mask initialization is in
// system_root.xml, the diagram in system_810.xml)
//
//   a ─┐
//   b ─┴─ cmult* (conjugated, full precision, latency MULT+ADD) = a·conj(b)
//          ─ c_to_ri1 ─┬ re ─ cmac_acc (acc)  ─┐
//                      └ im ─ cmac_acc (acc1) ─┴ ri_to_c ─ acc_out
//   acc_in ─ c_to_ri2 ─ re ─► acc.acc_in, im ─► acc1.acc_in
//   sync ─ Delay(MULT+ADD-1) ─ Counter ─ Relational(cnt == 0, latency 1) ─ rst
//   valid_in ─► acc1 ─► valid_out      (acc gets valid_in = 0, valid_out unused)
//
// Mask initialization:
//   bit_growth = ceil(log2(acc_len))
//   n_bits_out = n_bits_a + n_bits_b + 1 + bit_growth
//   bin_pt_out = bin_pt_a + bin_pt_b
// and cmult* gets conjugated = on, n_bits_ab = n_bits_out,
// bin_pt_ab = bin_pt_out, in_latency = conv_latency = 0, mult_latency,
// add_latency, multiplier_implementation. The stored cmult* is an older
// copy without pipeline_cmult_en (it defaults to off and the diagram has
// no product pipeline), so its latency is MULT_LATENCY + ADD_LATENCY.
// Products and sums are full precision and the convert only sign-extends,
// so the sums are exact integers.
//
// Counter: Count Limited, unsigned bit_growth bits, 0 .. acc_len-1, start 0,
// rst = delayed sync (free running: without sync rst still repeats every
// ACC_LEN cycles). rst = 1 the cycle after the counter shows 0.
//
// Timing (sync at S, first sample of the frame at S+1):
//   rst at S+MULT+ADD+1, aligned with the first product; then every
//   ACC_LEN cycles. acc_out / valid_out = 1 two cycles after each rst
//   (the first one after sync dumps the partial sum from before sync).
//   acc_in -> acc_out and valid_in -> valid_out: 2 cycles.
//
// Constraint A: c_to_ri2 reinterprets acc_in with binary point
// n_bits_out - bit_growth - 3 = N_BITS_A + N_BITS_B - 2, hardcoded, while
// the accumulator uses bin_pt_out = BIN_PT_A + BIN_PT_B. The relay Mux is
// Full precision, so if the two differ Simulink aligns the binary points and
// acc_out becomes wider than 2*n_bits_out with acc_in shifted. That cannot
// be expressed with fixed ports, so it is a $fatal here. The default
// (4_3 x 4_3) and dual_pol_cmac (always bin_pt = n_bits - 1) satisfy it.
//
// Parameters (mask names, stored defaults): ACC_LEN 128, N_BITS_A/BIN_PT_A
// 4/3, N_BITS_B/BIN_PT_B 4/3, MULT_LATENCY 1, ADD_LATENCY 1,
// MULTIPLIER_IMPLEMENTATION 2 (embedded multiplier core; 0 behavioral HDL,
// 1 standard core; resource only). QUANTIZATION, OVERFLOW, IN_LATENCY and
// CONV_LATENCY are greyed out on the mask and not used by the init script:
// declared only ($warning if IN/CONV_LATENCY are nonzero).
//
// Ports: a = {re, im} (2*N_BITS_A), b = {re, im} (2*N_BITS_B, the
// conjugated input), acc_in / acc_out = {re, im} (2*N_BITS_OUT each part
// signed with binary point BIN_PT_OUT), real parts in the MSBs.
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
// block = 'casper_library_correlator.slx/cmac'
// deviations = [
//   "Constraint A: the HDL stops with a $fatal unless BIN_PT_A+BIN_PT_B == N_BITS_A+N_BITS_B-2. Simulink accepts any binary points: c_to_ri2 hardcodes acc_in's binary point to n_bits_out-bit_growth-3, and the Full-precision relay Mux in acc/acc1 (system_871.xml Mux2) then makes acc_out wider than 2*n_bits_out and shifts acc_in.",
//   "IN_LATENCY and CONV_LATENCY are declared only and give a $warning when nonzero. In Simulink they are greyed out and the mask init always sets cmult* in_latency/conv_latency to '0' (system_root.xml init), so the behaviour matches.",
// ]
//
// [params.MULTIPLIER_IMPLEMENTATION]
// mask = 'multiplier_implementation'
// type = 'popup'
// [params.MULTIPLIER_IMPLEMENTATION.values]
// 0 = 'behavioral HDL'
// 1 = 'standard core'
// 2 = 'embedded multiplier core'
//
// [params.QUANTIZATION]
// mask = 'quantization'
// type = 'popup'
// note = 'declared only: greyed out and hidden on the mask (system_root.xml:175, Enabled/Visible off) and never passed to cmult*, so it has no effect in Simulink either'
// [params.QUANTIZATION.values]
// 0 = 'Truncate'
// 1 = 'Round  (unbiased: +/- Inf)'
// 2 = 'Round  (unbiased: Even Values)'
//
// [params.OVERFLOW]
// mask = 'overflow'
// type = 'popup'
// note = 'declared only: greyed out and hidden on the mask (system_root.xml:184) and never passed to cmult*, so it has no effect in Simulink either'
// [params.OVERFLOW.values]
// 0 = 'Wrap'
// 1 = 'Saturate'
// 2 = 'Flag as error'
//
// [hdl_only]
// BIT_GROWTH = 'derived from other parameters (do not override)'
// N_BITS_OUT = 'derived from other parameters (do not override)'
// BIN_PT_OUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// note = 'the Simulink names are not legal HDL identifiers'
// [ports.renamed]
// a = 'a+bi'
// b = 'c+di'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module cmac #(
    parameter int ACC_LEN                   = 128,
    parameter int N_BITS_A                  = 4,
    parameter int BIN_PT_A                  = 3,
    parameter int N_BITS_B                  = 4,
    parameter int BIN_PT_B                  = 3,
    parameter int QUANTIZATION              = 0,
    parameter int OVERFLOW                  = 0,
    parameter int MULT_LATENCY              = 1,
    parameter int ADD_LATENCY               = 1,
    parameter int IN_LATENCY                = 0,
    parameter int CONV_LATENCY              = 0,
    parameter int MULTIPLIER_IMPLEMENTATION = 2,
    // derived (mask initialization); not to be overridden
    parameter int BIT_GROWTH                = $clog2(ACC_LEN),
    parameter int N_BITS_OUT                = N_BITS_A + N_BITS_B + 1 + BIT_GROWTH,
    parameter int BIN_PT_OUT                = BIN_PT_A + BIN_PT_B
)(
    input  logic                    clk,
    input  logic [2*N_BITS_A-1:0]   a,
    input  logic [2*N_BITS_B-1:0]   b,
    input  logic [2*N_BITS_OUT-1:0] acc_in,
    input  logic                    sync,
    input  logic                    valid_in,
    output logic [2*N_BITS_OUT-1:0] acc_out,
    output logic                    valid_out
);

    initial begin
        if (ACC_LEN < 2)
            $fatal(1, "cmac: ACC_LEN must be >= 2 (bit_growth = 0 gives a 0-bit counter)");
        if (MULT_LATENCY + ADD_LATENCY < 1)
            $fatal(1, "cmac: MULT_LATENCY + ADD_LATENCY must be >= 1 (sync delay = sum - 1)");
        if (BIN_PT_A + BIN_PT_B != N_BITS_A + N_BITS_B - 2)
            $fatal(1, "cmac: constraint A, BIN_PT_A + BIN_PT_B (%0d) must equal N_BITS_A + N_BITS_B - 2 (%0d), the binary point c_to_ri2 hardcodes for acc_in",
                   BIN_PT_A + BIN_PT_B, N_BITS_A + N_BITS_B - 2);
        if (BIT_GROWTH != $clog2(ACC_LEN) || N_BITS_OUT != N_BITS_A + N_BITS_B + 1 + BIT_GROWTH
            || BIN_PT_OUT != BIN_PT_A + BIN_PT_B)
            $fatal(1, "cmac: BIT_GROWTH / N_BITS_OUT / BIN_PT_OUT are derived, do not override");
        if (IN_LATENCY != 0 || CONV_LATENCY != 0)
            $warning("cmac: IN_LATENCY / CONV_LATENCY are unused (the mask forces 0 into cmult)");
    end

    // ── a · conj(b) ──────────────────────────────────────────────────────────
    logic [2*N_BITS_OUT-1:0] prod;

    cmult #(
        .N_BITS_A(N_BITS_A), .BIN_PT_A(BIN_PT_A), .N_BITS_B(N_BITS_B), .BIN_PT_B(BIN_PT_B),
        .N_BITS_AB(N_BITS_OUT), .BIN_PT_AB(BIN_PT_OUT), .QUANTIZATION(0), .OVERFLOW(0),
        .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY), .CONV_LATENCY(0),
        .IN_LATENCY(0), .PIPELINE_CMULT_EN(0), .CONJUGATED(1),
        .MULTIPLIER_IMPLEMENTATION(MULTIPLIER_IMPLEMENTATION)
    ) u_cmult (.clk(clk), .a(a), .b(b), .ab(prod));

    logic [N_BITS_OUT-1:0] prod_re, prod_im, acc_in_re, acc_in_im, out_re, out_im;

    c_to_ri #(.N_BITS(N_BITS_OUT), .BIN_PT(BIN_PT_OUT)) u_c_to_ri1 (
        .c(prod), .re(prod_re), .im(prod_im));
    c_to_ri #(.N_BITS(N_BITS_OUT), .BIN_PT(N_BITS_A + N_BITS_B - 2)) u_c_to_ri2 (
        .c(acc_in), .re(acc_in_re), .im(acc_in_im));

    // ── sync -> rst ──────────────────────────────────────────────────────────
    logic                  sync_d, rst;
    logic [BIT_GROWTH-1:0] cnt, zero;

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(MULT_LATENCY + ADD_LATENCY - 1)) u_sync_dly (
        .clk(clk), .din(sync), .dout(sync_d));

    counter #(
        .COUNTER_TYPE(1), .NBITS(BIT_GROWTH), .COUNT_TO_VAL(ACC_LEN - 1), .COUNT_DIR(0),
        .INIT_VAL(0), .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0), .RST_VAL(0)
    ) u_cnt (.clk(clk), .rst(sync_d), .enable(1'b1), .dout(cnt));

    constant #(.NBITS(BIT_GROWTH), .VAL(0)) u_zero (.out(zero));

    relational #(.NBITS(BIT_GROWTH), .COMP(0), .LATENCY(1), .SIGNED(0)) u_is_zero (
        .clk(clk), .a(cnt), .b(zero), .out(rst));

    // ── accumulate and relay ─────────────────────────────────────────────────
    cmac_acc #(.N_BITS(N_BITS_OUT)) u_acc (
        .clk(clk), .rst(rst), .din(prod_re), .acc_in(acc_in_re), .valid_in(1'b0),
        .acc_out(out_re), .valid_out());

    cmac_acc #(.N_BITS(N_BITS_OUT)) u_acc1 (
        .clk(clk), .rst(rst), .din(prod_im), .acc_in(acc_in_im), .valid_in(valid_in),
        .acc_out(out_im), .valid_out(valid_out));

    ri_to_c #(.NBITS(N_BITS_OUT)) u_ri_to_c (.re(out_re), .im(out_im), .c(acc_out));

endmodule
