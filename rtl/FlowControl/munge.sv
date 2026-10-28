// munge — casper_library_flow_control/munge: split din into divisions and
// concatenate them in a given order (combinational, no clock)
//
// Both vectors list the divisions from the MSB, as Simulink does: munge_init.m
// splits din with bus_expand, whose output port k is the k-th division from
// the MSB (bus_expand_init.m slices with base 'MSB of Input'), and joins
// split/(order(j)+1) into bus_create input j, whose input 1 is the MSB. So
// division k of din occupies the bits below the first k divisions, and
//   dout = { din division ORDER[0], din division ORDER[1], ... }   (MSB first)
// A division of size 0 has no bits: the ORDER entries naming it are dropped.
// ORDER may repeat or leave out divisions when the sizes differ (see the
// mapping). With DIVISIONS = 1 dout = din and ORDER is ignored.
//
// Vector parameters (DIV_SIZE, ORDER) are packed 32-bit elements, first
// element in the MSBs, so they read like the mask vector:
//   .DIV_SIZE({32'd32, 32'd0, 32'd16, 32'd16})   // div_size = [32 0 16 16]
//   .ORDER({32'd3, 32'd0, 32'd1, 32'd2})          // order    = [3 0 1 2]
// They have no declared type, so their length is $bits / 32 of the value
// given. DIV_SIZE has one element (every division that size) or DIVISIONS.
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
// block = 'casper_library_flow_control.slx/munge'
// deviations = [
//   'Simulink takes the din width from the input signal and bus_expand slices from its MSB, so a din wider than the sum of div_size has its extra LSBs ignored; the HDL fixes the din width at the sum of DIV_SIZE (DIVISIONS * DIV_SIZE for one element). With divisions = 1 Simulink passes din of any width through; the HDL din is DIV_SIZE[0] bits.',
//   'With divisions > 1 and only one non-zero size (div_size a scalar, or one non-zero element), munge_init.m sets divisions_mod to the number of non-zero sizes and builds a one-output bus_expand and a one-input join, so Simulink builds only when order, without the entries naming zero-size divisions, is a single entry naming the non-zero division (a scalar div_size: order = [0], dout = the MSB division); see docs/bugs.md bug 21. The HDL gives every division of a scalar DIV_SIZE that size and accepts any ORDER. With several non-zero sizes the join has one input per order entry in both.',
//   'When order names two or more zero-size divisions, munge_init.m deletes their entries at positions found before any deletion, so once an earlier deletion has shifted the vector it drops the wrong entries or fails (docs/bugs.md bug 22); the HDL drops every entry that names a zero-size division.',
//   "Simulink reinterprets dout as arith_type_out / bin_pt_out; the HDL outputs the raw bits (identical). munge_init.m also checks bin_pt_out against a word size that, with a scalar div_size, it computes wrongly (div_size*(order+1) summed), so Simulink may reject a valid bin_pt_out; this has no HDL counterpart.",
// ]
//
// [params.DIVISIONS]
// mask = 'divisions'
// type = 'edit'
// note = 'same parameter; DIVISIONS < 1 (an empty block in Simulink) is rejected'
//
// [params.DIV_SIZE]
// mask = 'div_size'
// type = 'edit'
// note = "packed 32-bit elements, first in the MSBs: {32'd16, 32'd8} is the mask vector [16 8]; one element = every division that size"
//
// [params.ORDER]
// mask = 'order'
// type = 'edit'
// note = "packed 32-bit elements, first in the MSBs: {32'd1, 32'd0} is the mask vector [1 0]"
//
// [hdl_only]
//
// [mask_missing]
// arith_type_out = 'output type only (Reinterpret): the HDL outputs the raw bits'
// bin_pt_out = 'output type only (Reinterpret): the HDL outputs the raw bits'
//
// [ports]
// note = 'din / dout are the Simulink port names; both are raw bit vectors'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module munge #(
    /* DIVISIONS: number of divisions of din (mask divisions) */
    parameter int DIVISIONS = 4,
    /* DIV_SIZE: division sizes in bits, MSB division first (mask div_size) */
    parameter DIV_SIZE = {32'd32, 32'd0, 32'd16, 32'd16},
    /* ORDER: din division of each dout division, MSB first (mask order) */
    parameter ORDER = {32'd3, 32'd0, 32'd1, 32'd2},
    localparam int DS_LEN = $bits(DIV_SIZE) / 32,
    localparam int ORDER_LEN = $bits(ORDER) / 32,
    localparam int DIN_WIDTH = din_width(),
    localparam int DOUT_WIDTH = (DIVISIONS == 1) ? DIN_WIDTH : dout_width()
)(
    input  logic [DIN_WIDTH-1:0]  din,
    output logic [DOUT_WIDTH-1:0] dout
);

/* size of division k (MSB first) */
function automatic int div_size(input int k);
    return (DS_LEN == 1) ? DIV_SIZE[31:0] : DIV_SIZE[32*(DS_LEN-1-k) +: 32];
endfunction

/* ORDER element j */
function automatic int order(input int j);
    return ORDER[32*(ORDER_LEN-1-j) +: 32];
endfunction

function automatic int din_width();
    int w = 0;
    for (int k = 0; k < DIVISIONS; k++)
        w += div_size(k);
    return w;
endfunction

function automatic int dout_width();
    int w = 0;
    for (int j = 0; j < ORDER_LEN; j++)
        w += div_size(order(j));
    return w;
endfunction

/* LSB of din division k: below it are the divisions after it */
function automatic int din_lsb(input int k);
    int b = 0;
    for (int i = k + 1; i < DIVISIONS; i++)
        b += div_size(i);
    return b;
endfunction

/* LSB of dout division j */
function automatic int dout_lsb(input int j);
    int b = 0;
    for (int i = j + 1; i < ORDER_LEN; i++)
        b += div_size(order(i));
    return b;
endfunction

initial
begin
    if (DIVISIONS < 1)
        $fatal(1, "Error: DIVISIONS = %0d must be at least 1.", DIVISIONS);
    if ($bits(DIV_SIZE) % 32 != 0 || $bits(ORDER) % 32 != 0)
        $fatal(1, "Error: DIV_SIZE and ORDER must be packed 32-bit elements.");
    if (DS_LEN != 1 && DS_LEN != DIVISIONS)
        $fatal(1, "Error: DIV_SIZE has %0d elements; it needs 1 or DIVISIONS = %0d.", DS_LEN, DIVISIONS);
    for (int k = 0; k < DS_LEN; k++)
        if (div_size(k) < 0)
            $fatal(1, "Error: DIV_SIZE element %0d is negative.", k);
    if (DIN_WIDTH < 1)
        $fatal(1, "Error: the division sizes must not all be 0.");
    if (DIVISIONS > 1)
        for (int j = 0; j < ORDER_LEN; j++)
            if (order(j) < 0 || order(j) > DIVISIONS - 1)
                $fatal(1, "Error: ORDER element %0d = %0d must be in 0..%0d.", j, order(j), DIVISIONS - 1);
    if (DOUT_WIDTH < 1)
        $fatal(1, "Error: ORDER names only divisions of size 0.");
end

generate
    if (DIVISIONS == 1) begin : GEN_PASS
        assign dout = din;
    end else begin : GEN_MUNGE
        for (genvar j = 0; j < ORDER_LEN; j++) begin : GEN_DIV
            if (div_size(order(j)) > 0) begin : GEN_BITS
                assign dout[dout_lsb(j) +: div_size(order(j))] = din[din_lsb(order(j)) +: div_size(order(j))];
            end
        end
    end
endgenerate

endmodule
