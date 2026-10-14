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
// SIMULINK-COMPAT: the RAM's power-on contents reproduce this block's
// initVector = [1:36*8] (system_928.xml:369), the same vector as
// xeng_descramble's; the init code is xeng_descramble's RAM_INIT.
//
// Parameters: N_BITS, ACC_LEN, DEMUX_FACTOR are the mask parameters (stored
// defaults 8, 256, 1); PLATFORM is passed to the RAM. With the defaults:
// W = 25, P = 32, OW = 256, DEL = 84, CNT = 10.
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
// block = 'casper_library_correlator.slx/xeng_descramble_4ant'
// deviations = [
//   "Power-on RAM contents are reproduced only for PLATFORM = GENERIC: the library RAM (system_928.xml:369, latency 2) has initVector = [1:36*8], which xeng_descramble's RAM_INIT reproduces (SIMULINK-COMPAT; narrow word n = min(n+1, 2^OW-1) for n < min(288, (E+1)*D), truncated to the depth, e.g. 11 words by default). Vendor RAMs power up to 0.",
//   "Read/write collision: Simulink returns NaN on port A when port B ('No Read On Write') writes the same wide word in the same cycle (xlDPBRAM.sgm). The HDL returns defined data. This does not happen with legal xeng traffic.",
// ]
//
// break_link = 'mlib_devel bug 11 (docs/bugs.md): the x_cast mask initialization sets parameters of blocks inside itself, which Simulink refuses inside a resolved library link (Attempting to override parameters of .../x_cast which is inside a library link), so the block is placed as an unlinked copy (LinkStatus inactive). Verified in MATLAB R2021a with sets 0, 1 and 2.'
//
// [hdl_only]
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// W = 'derived from other parameters (do not override)'
// P = 'derived from other parameters (do not override)'
// OW = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

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
