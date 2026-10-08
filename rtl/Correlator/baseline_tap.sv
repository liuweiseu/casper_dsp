// baseline_tap — casper_library baseline_tap, one X-engine tap per antenna
// separation (casper_library_correlator.slx, Block SID 2; baseline_tap_init.m)
//
//   a_del  ─ delay(ACC_LEN) ─ Delay(1) ─┬─ a_del_out
//                                       └─ dual_pol_cmac.a1
//   a_ndel ─ Delay(1) ─ a_ndel_out;  a_end ─ Delay(1) ─ a_end_out
//   rst    ─ Delay(1) ─┬─ rst_out
//                      └─ dual_pol_cmac.sync
//   cnt : Counter, Count Limited 0 .. N_ANTS*ACC_LEN-1, unsigned
//         ANT_BITS+BIT_GROWTH bits, start 0, rst = rst (undelayed)
//   sel = (cnt < ANT_SEP*ACC_LEN)                     (Relational, latency 0)
//   a2  = Mux(sel, d0 = a_ndel, d1 = a_end, latency 1) -> dual_pol_cmac.a2
//   sync_out = sync1                                  (straight through)
//
// Frame alignment: rst at t0 resets the counter (cnt = 0 at t0+1) and
// reaches the cmac as sync at t0+1. The first sample of the frame, at t0+1,
// passes the latency-1 Mux and arrives with the cmac's frame start at t0+2.
// For the first ANT_SEP*ACC_LEN samples of each N_ANTS*ACC_LEN frame the
// conjugated input is a_end (the wrapped-around antennas), afterwards a_ndel.
// a_del reaches the cmac ACC_LEN+1 cycles late, a_ndel/a_end 1 cycle late
// (through the Mux), so a1 lags a2 by ACC_LEN samples. Each tap adds
// ACC_LEN+1 to a_del and 1 to a_ndel, a_end and rst; sync passes unchanged.
//
// Parameters (mask names, stored defaults): N_ANTS 4, ANT_SEP 1, N_BITS 4,
// ACC_LEN 32, ADD_LATENCY 1, MULT_LATENCY 2, BRAM_LATENCY 2, MULT_TYPE 2,
// USE_BRAM_DELAY 1.
//   MULT_TYPE: 0 = behavioral HDL, 1 = embedded multiplier core,
//              2 = standard core (resource only, passed to dual_pol_cmac)
//   USE_BRAM_DELAY: 1 = delay_bram, 0 = delay_slr (resource only). With
//              delay_bram, ACC_LEN <= BRAM_LATENCY+1 is the delay_bram mask
//              error, here a $fatal.
//   PLATFORM is passed to delay_bram.
// ANT_SEP*ACC_LEN must fit the ANT_BITS+BIT_GROWTH-bit Constant ($fatal
// otherwise; in xeng ANT_SEP <= N_ANTS/2, so it always fits).
// Derived: BIT_GROWTH = ceil(log2(ACC_LEN)), ANT_BITS = ceil(log2(N_ANTS)),
// N_BITS_OUT = 2*N_BITS + 1 + BIT_GROWTH.
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
// block = 'casper_library_correlator.slx/baseline_tap'
// deviations = [
//   "ANT_SEP*ACC_LEN must fit the ceil(log2 N_ANTS)+ceil(log2 ACC_LEN)-bit Constant, or the HDL stops with a $fatal; Simulink's Xilinx Constant would quantize it (round/saturate, see xlRegister.sgm's constant convention) and build. Inside xeng ANT_SEP <= N_ANTS/2, so the value always fits.",
// ]
//
// [hdl_only]
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// N_BITS_OUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module baseline_tap #(
    parameter int    N_ANTS         = 4,
    parameter int    ANT_SEP        = 1,
    parameter int    N_BITS         = 4,
    parameter int    ACC_LEN        = 32,
    parameter int    ADD_LATENCY    = 1,
    parameter int    MULT_LATENCY   = 2,
    parameter int    BRAM_LATENCY   = 2,
    parameter int    MULT_TYPE      = 2,
    parameter int    USE_BRAM_DELAY = 1,
    parameter string PLATFORM       = "GENERIC",
    // derived; not to be overridden
    parameter int    N_BITS_OUT     = 2 * N_BITS + 1 + $clog2(ACC_LEN)
)(
    input  logic                    clk,
    input  logic [4*N_BITS-1:0]     a_del,
    input  logic [4*N_BITS-1:0]     a_ndel,
    input  logic [4*N_BITS-1:0]     a_end,
    input  logic [8*N_BITS_OUT-1:0] acc_in,
    input  logic                    valid_in,
    input  logic                    rst,
    input  logic                    sync1,
    output logic [4*N_BITS-1:0]     a_del_out,
    output logic [4*N_BITS-1:0]     a_ndel_out,
    output logic [4*N_BITS-1:0]     a_end_out,
    output logic [8*N_BITS_OUT-1:0] acc_out,
    output logic                    valid_out,
    output logic                    rst_out,
    output logic                    sync_out
);

    localparam int CNT_BITS = $clog2(N_ANTS) + $clog2(ACC_LEN);
    localparam int MULT_IMP = (MULT_TYPE == 2) ? 1 : (MULT_TYPE == 1) ? 2 : 0;
    localparam int W        = 4 * N_BITS;

    initial begin
        if (N_BITS_OUT != 2 * N_BITS + 1 + $clog2(ACC_LEN))
            $fatal(1, "baseline_tap: N_BITS_OUT is derived, do not override");
        if (USE_BRAM_DELAY != 0 && ACC_LEN <= BRAM_LATENCY + 1)
            $fatal(1, "baseline_tap: delay_bram value ACC_LEN (%0d) must be greater than BRAM_LATENCY + 1 (%0d)",
                   ACC_LEN, BRAM_LATENCY + 1);
        if (ANT_SEP * ACC_LEN >= (1 << CNT_BITS))
            $fatal(1, "baseline_tap: ANT_SEP*ACC_LEN (%0d) does not fit the %0d-bit counter constant",
                   ANT_SEP * ACC_LEN, CNT_BITS);
    end

    // ── a_del: delay(ACC_LEN) + Delay3(1) ────────────────────────────────────
    logic [W-1:0] a_del_d;

    generate
        if (USE_BRAM_DELAY != 0) begin : GEN_BRAM
            delay_bram #(.BITWIDTH(W), .DELAY_LEN(ACC_LEN), .PLATFORM(PLATFORM)) u_delay (
                .clk(clk), .din(a_del), .dout(a_del_d));
        end else begin : GEN_SRL
            delay_srl #(.BITWIDTH(W), .DELAY_LEN(ACC_LEN), .USE_ENABLE(0), .USE_RST(0)) u_delay (
                .clk(clk), .rst(1'b0), .en(1'b1), .din(a_del), .dout(a_del_d));
        end
    endgenerate

    delay #(.LATENCY(1), .BITWIDTH(W)) u_delay3 (.clk(clk), .din(a_del_d), .dout(a_del_out));
    delay #(.LATENCY(1), .BITWIDTH(W)) u_delay7 (.clk(clk), .din(a_ndel), .dout(a_ndel_out));
    delay #(.LATENCY(1), .BITWIDTH(W)) u_delay8 (.clk(clk), .din(a_end), .dout(a_end_out));
    delay #(.LATENCY(1), .BITWIDTH(1)) u_delay1 (.clk(clk), .din(rst), .dout(rst_out));

    assign sync_out = sync1;

    // ── antenna select: a_end for the first ANT_SEP*ACC_LEN samples ──────────
    logic [CNT_BITS-1:0] cnt, sep;
    logic                sel;

    counter #(
        .COUNTER_TYPE(1), .NBITS(CNT_BITS), .COUNT_TO_VAL(N_ANTS * ACC_LEN - 1), .COUNT_DIR(0),
        .INIT_VAL(0), .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0), .RST_VAL(0)
    ) u_cnt (.clk(clk), .rst(rst), .enable(1'b1), .dout(cnt));

    constant #(.NBITS(CNT_BITS), .VAL(ANT_SEP * ACC_LEN)) u_sep (.out(sep));

    relational #(.NBITS(CNT_BITS), .COMP(2), .LATENCY(0), .SIGNED(0)) u_lt (
        .clk(clk), .a(cnt), .b(sep), .out(sel));

    logic [W-1:0] mux_in [2];
    logic [W-1:0] a2;
    assign mux_in[0] = a_ndel;
    assign mux_in[1] = a_end;
    multiplexer #(.NBITS(W), .NINPUTS(2), .LATENCY(1)) u_mux (
        .clk(clk), .din(mux_in), .sel(sel), .dout(a2));

    dual_pol_cmac #(
        .ACC_LEN(ACC_LEN), .N_BITS_IN(N_BITS), .BIN_PT_IN(N_BITS - 1),
        .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
        .MULTIPLIER_IMPLEMENTATION(MULT_IMP)
    ) u_dual_pol_cmac (
        .clk(clk), .a1(a_del_out), .a2(a2), .acc_in(acc_in), .sync(rst_out),
        .valid_in(valid_in), .acc_out(acc_out), .valid_out(valid_out));

endmodule
