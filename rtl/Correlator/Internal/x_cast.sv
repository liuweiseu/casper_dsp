// x_cast — field reorder + sign extension inside casper_library's
// xeng_descramble (casper_library_correlator.slx, system_588; identical in
// xeng_descramble_4ant, system_1107). Not a library block.
//
// din holds 8 signed N_BITS_IN-bit fields, field f at din[f*N_BITS_IN +: N_BITS_IN]
// (f = 0 at the LSB). Concat input j = 1..8 (j = 1 in the MSBs) is field
// bit_offsets(j), sign-extended to N_BITS_OUT bits (Reinterpret + Convert,
// latency 0):
//
//   demux 8: bit_offsets = [0 1 2 3 4 5 6 7]
//   demux 4: bit_offsets = [1 0 3 2 5 4 7 6]
//   demux 2: bit_offsets = [3 2 1 0 7 6 5 4]
//   demux 1: bit_offsets = [7 6 5 4 3 2 1 0]
//
// i.e. bit_offsets(j) = (j-1) XOR (8/DEMUX_FACTOR - 1): the output is cut
// into DEMUX_FACTOR blocks of 8/DEMUX_FACTOR fields, the blocks are put in
// reverse order and the fields inside each block keep their order. Together
// with the dual-port RAM's narrow read port (narrow address k of a wide word
// = bits [k*OW +: OW], LSB first), xeng_descramble reads each element out
// MSB field first.
//
// Mask parameters: n_bits_in (W), n_bits_out (P), fix_pnt_pos (binary
// point; only a type annotation, declared only) and demux_factor (1, 2, 4
// or 8).
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
// block = 'casper_library_correlator.slx/xeng_descramble/x_cast'
// deviations = [
//   "N_BITS_OUT < N_BITS_IN is a $fatal, while the diagram's Convert blocks (system_588.xml: Signed n_bits_out/fix_pnt_pos, Truncate, Wrap) would silently drop the upper bits of each field; for N_BITS_OUT >= N_BITS_IN both are an exact sign extension.",
//   'FIX_PNT_POS is declared only: in the diagram it is the binary point of both the Reinterpret and the Convert, so it never changes the bits, and the HDL ignores it.',
// ]
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// note = 'masked subsystem (system_588.xml, mask in system_411.xml:1277-1309); identical copy in xeng_descramble_4ant (system_1107.xml)'
// [ports.renamed]
// din = 'in'
// dout = 'out'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module x_cast #(
    parameter int N_BITS_IN    = 16,
    parameter int N_BITS_OUT   = 16,
    parameter int FIX_PNT_POS  = 6,
    parameter int DEMUX_FACTOR = 8
)(
    input  logic [8*N_BITS_IN-1:0]  din,
    output logic [8*N_BITS_OUT-1:0] dout
);

    initial begin
        if (DEMUX_FACTOR != 1 && DEMUX_FACTOR != 2 && DEMUX_FACTOR != 4 && DEMUX_FACTOR != 8)
            $fatal(1, "x_cast: DEMUX_FACTOR must be 1, 2, 4 or 8 (got %0d)", DEMUX_FACTOR);
        if (N_BITS_OUT < N_BITS_IN)
            $fatal(1, "x_cast: N_BITS_OUT (%0d) must be >= N_BITS_IN (%0d)", N_BITS_OUT, N_BITS_IN);
    end

    localparam int FLIP = 8 / DEMUX_FACTOR - 1;

    for (genvar j = 0; j < 8; j++) begin : GEN_FIELD
        // Concat input j+1 (from the MSB) takes field j ^ FLIP (from the LSB)
        logic signed [N_BITS_IN-1:0] field;
        assign field = din[(j ^ FLIP) * N_BITS_IN +: N_BITS_IN];
        assign dout[(7 - j) * N_BITS_OUT +: N_BITS_OUT] = N_BITS_OUT'(field);
    end

endmodule
