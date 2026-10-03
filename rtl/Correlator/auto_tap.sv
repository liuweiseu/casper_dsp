// auto_tap — casper_library auto_tap, the first tap of the X-engine
// (casper_library_correlator.slx, Block SID 1; auto_tap_init.m)
//
//   a_del, a_ndel, sync_in, rst_out: passed straight through (0 cycles)
//   dual_pol_cmac(a1 = a_del, a2 = a_ndel, acc_in, sync = sync_in, valid_in)
//        -> acc_out, valid_out
//   a_end_out = a_loop delayed by D             (delay_bram, or delay_slr)
//   sync_out  = sync_delay(sync_in, S)
//
//   D = (ACC_LEN-1)*ceil(N_ANTS/2) + ceil(N_ANTS/2) - floor(N_ANTS/2)
//     = (ACC_LEN-1)*ceil(N_ANTS/2) + N_ANTS%2           (auto_tap_init.m)
//   S = ADD_LATENCY + MULT_LATENCY + ACC_LEN + floor(N_ANTS/2 + 1) + 1
//   With the stored mask values (N_ANTS 4, ACC_LEN 64, ADD 1, MULT 2):
//   D = 126 and S = 71, the DelayLen values stored in the .slx.
//
// a_loop is fed back from the last baseline_tap's a_del_out in xeng. Every
// baseline_tap delays a_del by ACC_LEN+1, so with M = floor(N_ANTS/2)
// baseline taps the loop adds up to M*(ACC_LEN+1) + D = N_ANTS*ACC_LEN:
// a_end_out lags the antenna stream by exactly N_ANTS*ACC_LEN samples.
// rst_out (= sync_in) drives the next tap's counter.
//
// Parameters (mask names, stored defaults): N_ANTS 4, N_BITS 4, ACC_LEN 64,
// ADD_LATENCY 1, MULT_LATENCY 2, BRAM_LATENCY 2, MULT_TYPE 0,
// USE_BRAM_DELAY 1. auto_tap_init.m has different defaults (acc_len 32,
// mult_type 1); the stored mask values are used.
//   MULT_TYPE: 0 = behavioral HDL, 1 = embedded multiplier core,
//              2 = standard core (resource only, passed to dual_pol_cmac)
//   USE_BRAM_DELAY: 1 = delay_bram, 0 = delay_slr (resource only; both are
//              exact delays). With delay_bram, D <= BRAM_LATENCY+1 is the
//              delay_bram mask error, here a $fatal. BRAM_LATENCY has no
//              other effect: delay_bram's total delay is D either way.
//   N_SIMULTAN is disabled on the mask and not read by the init script:
//              declared only.
//   PLATFORM is passed to delay_bram.
// Derived: N_BITS_OUT = 2*N_BITS + 1 + ceil(log2(ACC_LEN)).

module auto_tap #(
    parameter int    N_ANTS         = 4,
    parameter int    N_SIMULTAN     = 2,
    parameter int    N_BITS         = 4,
    parameter int    ACC_LEN        = 64,
    parameter int    ADD_LATENCY    = 1,
    parameter int    MULT_LATENCY   = 2,
    parameter int    BRAM_LATENCY   = 2,
    parameter int    MULT_TYPE      = 0,
    parameter int    USE_BRAM_DELAY = 1,
    parameter string PLATFORM       = "GENERIC",
    // derived; not to be overridden
    parameter int    N_BITS_OUT     = 2 * N_BITS + 1 + $clog2(ACC_LEN)
)(
    input  logic                    clk,
    input  logic [4*N_BITS-1:0]     a_del,
    input  logic [4*N_BITS-1:0]     a_ndel,
    input  logic [4*N_BITS-1:0]     a_loop,
    input  logic [8*N_BITS_OUT-1:0] acc_in,
    input  logic                    valid_in,
    input  logic                    sync_in,
    output logic [4*N_BITS-1:0]     a_del_out,
    output logic [4*N_BITS-1:0]     a_ndel_out,
    output logic [4*N_BITS-1:0]     a_end_out,
    output logic [8*N_BITS_OUT-1:0] acc_out,
    output logic                    valid_out,
    output logic                    rst_out,
    output logic                    sync_out
);

    localparam int D = (ACC_LEN - 1) * ((N_ANTS + 1) / 2) + (N_ANTS % 2);
    localparam int S = ADD_LATENCY + MULT_LATENCY + ACC_LEN + (N_ANTS / 2 + 1) + 1;
    localparam int MULT_IMP = (MULT_TYPE == 2) ? 1 : (MULT_TYPE == 1) ? 2 : 0;

    initial begin
        if (N_BITS_OUT != 2 * N_BITS + 1 + $clog2(ACC_LEN))
            $fatal(1, "auto_tap: N_BITS_OUT is derived, do not override");
        if (USE_BRAM_DELAY != 0 && D != 0 && D <= BRAM_LATENCY + 1)
            $fatal(1, "auto_tap: delay_bram value (%0d) must be greater than BRAM_LATENCY + 1 (%0d)",
                   D, BRAM_LATENCY + 1);
    end

    assign a_del_out  = a_del;
    assign a_ndel_out = a_ndel;
    assign rst_out    = sync_in;

    dual_pol_cmac #(
        .ACC_LEN(ACC_LEN), .N_BITS_IN(N_BITS), .BIN_PT_IN(N_BITS - 1),
        .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
        .MULTIPLIER_IMPLEMENTATION(MULT_IMP)
    ) u_dual_pol_cmac (
        .clk(clk), .a1(a_del), .a2(a_ndel), .acc_in(acc_in), .sync(sync_in),
        .valid_in(valid_in), .acc_out(acc_out), .valid_out(valid_out));

    generate
        if (USE_BRAM_DELAY != 0) begin : GEN_BRAM
            delay_bram #(.BITWIDTH(4 * N_BITS), .DELAY_LEN(D), .PLATFORM(PLATFORM)) u_delay (
                .clk(clk), .din(a_loop), .dout(a_end_out));
        end else begin : GEN_SRL
            delay_srl #(.BITWIDTH(4 * N_BITS), .DELAY_LEN(D), .USE_ENABLE(0), .USE_RST(0)) u_delay (
                .clk(clk), .rst(1'b0), .en(1'b1), .din(a_loop), .dout(a_end_out));
        end
    endgenerate

    sync_delay #(.DELAY_LEN(S)) u_sync_delay (.clk(clk), .din(sync_in), .dout(sync_out));

endmodule
