// cmac_acc — accumulate-and-relay cell inside casper_library's cmac
// (casper_library_correlator.slx, system_871 "acc" / system_886 "acc1"; not
// a library block, the two copies are identical)
//
//   Convert1 : din -> Signed N_BITS (no-op, din already has that format)
//   Accumulator (Add, N_BITS, Wrap, rst on, hasbypass on, latency 1):
//              q <= rst ? din : q + din            (power-on 0)
//   Mux2 (sel = rst, latency 2): acc_out   = rst ? q : acc_in
//   Mux3 (sel = rst, latency 2): valid_out = rst ? 1 : valid_in
//
// hasbypass is the Xilinx Accumulator option "Reinitialize with input 'b'
// on reset" (its hardware note, e.g. in casper_library/Tests/xeng_test.mdl):
// on reset the accumulator loads the current input instead of clearing, so
// consecutive integrations have no gap. On the rst cycle q still holds the
// finished sum, which the muxes put on acc_out two cycles later; at all
// other times acc_in is relayed with the same 2-cycle delay.
//
// The Delay / Delay1 blocks in the diagram have latency 0 (wires).
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
// block = 'casper_library_correlator.slx/cmac/acc'
// deviations = [
//   "The HDL assumes acc_in and din share one binary point; in the diagram Mux2 (system_871.xml) is Full precision, so if acc_in's binary point differs from the Accumulator's (bin_pt_out) Simulink widens acc_out and shifts acc_in (cmac's 'constraint A', which cmac.sv rejects with $fatal).",
// ]
//
// [hdl_only]
// N_BITS = "parent cmac's n_bits_out (Accumulator n_bits)"
//
// [mask_missing]
//
// [ports]
// note = 'also models the identical copy cmac/acc1 (system_886.xml, imaginary part); same ports rst, din, acc_in, valid_in -> acc_out, valid_out'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module cmac_acc #(
    parameter int N_BITS = 16
)(
    input  logic              clk,
    input  logic              rst,
    input  logic [N_BITS-1:0] din,
    input  logic [N_BITS-1:0] acc_in,
    input  logic              valid_in,
    output logic [N_BITS-1:0] acc_out,
    output logic              valid_out
);

    // ── Accumulator (hasbypass: reinitialize with din on rst) ────────────────
    logic [N_BITS-1:0] q, q_next;
    assign q_next = rst ? din : q + din;

    register #(.BITWIDTH(N_BITS), .USE_RST(0), .USE_ENABLE(0), .INIT_VAL(0)) u_acc (
        .clk(clk), .rst(1'b0), .en(1'b1), .d(q_next), .q(q));

    // ── relay muxes ──────────────────────────────────────────────────────────
    logic [N_BITS-1:0] dmux_in [2];
    assign dmux_in[0] = acc_in;
    assign dmux_in[1] = q;
    multiplexer #(.NBITS(N_BITS), .NINPUTS(2), .LATENCY(2)) u_mux_data (
        .clk(clk), .din(dmux_in), .sel(rst), .dout(acc_out));

    logic [0:0] vmux_in [2];
    logic [0:0] vmux_out;
    assign vmux_in[0] = valid_in;
    assign vmux_in[1] = 1'b1;
    multiplexer #(.NBITS(1), .NINPUTS(2), .LATENCY(2)) u_mux_valid (
        .clk(clk), .din(vmux_in), .sel(rst), .dout(vmux_out));
    assign valid_out = vmux_out[0];

endmodule
