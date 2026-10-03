// xeng_descramble_4ant — casper_library 4-antenna X-engine descrambler
// (casper_library_correlator.slx, Block SID 928; no _init.m, mask
// initialization in system_root.xml with num_ants = 4 hardcoded)
//
// Structurally xeng_descramble (system_411) with NUM_ANTS = 4. The diffs of
// the stored diagrams (system_928/973/995/1107 vs 411/456/478/588):
//   - Dual Port RAM latency 2, valid_out Delay 2 and sync_out Logical
//     latency 2 (all 1 in xeng_descramble)            -> RAM_LATENCY = 2
//   - write_ctrl: Counter2 is replaced by the constant 9. For 4 antennas
//     PIVOT = E-1 = 9, so Counter2 (PIVOT .. E-1, start PIVOT) is constant 9
//     anyway: no functional difference.
//   - write_ctrl's negedge_delay is an inline copy of casper_library_misc
//     negedge_delay (identical diagram; its stale link data names the inner
//     edge detector "Both", but the stored detector is the falling-edge one,
//     AND(~in, Delay(in)), as in the library).
//   - read_ctrl and x_cast are identical.
// So it is a thin wrapper around xeng_descramble.
//
// Parameters: N_BITS, ACC_LEN, DEMUX_FACTOR are the mask parameters (stored
// defaults 8, 256, 1); PLATFORM is passed to the RAM. With the defaults:
// W = 25, P = 32, OW = 256, DEL = 84, CNT = 10.

module xeng_descramble_4ant #(
    parameter int    N_BITS       = 8,
    parameter int    ACC_LEN      = 256,
    parameter int    DEMUX_FACTOR = 1,
    parameter string PLATFORM     = "GENERIC",
    // derived (mask initialization); not to be overridden
    parameter int    W            = 2 * N_BITS + $clog2(ACC_LEN + 1),
    parameter int    P            = 1 << $clog2(W),
    parameter int    OW           = 8 * P / DEMUX_FACTOR
)(
    input  logic           clk,
    input  logic [8*W-1:0] acc,
    input  logic           valid,
    input  logic           sync,
    input  logic           win_valid,
    output logic [OW-1:0]  acc_out,
    output logic           valid_out,
    output logic           sync_out
);

    xeng_descramble #(
        .NUM_ANTS(4), .N_BITS(N_BITS), .ACC_LEN(ACC_LEN), .DEMUX_FACTOR(DEMUX_FACTOR),
        .RAM_LATENCY(2), .PLATFORM(PLATFORM)
    ) u_descramble (
        .clk(clk), .acc(acc), .valid(valid), .sync(sync), .win_valid(win_valid),
        .acc_out(acc_out), .valid_out(valid_out), .sync_out(sync_out));

endmodule
