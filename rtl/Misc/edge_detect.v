


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
// block = 'casper_library_misc.slx/edge_detect'
// deviations = []
//
// [params.EDGE]
// mask = 'edge'
// type = 'popup'
// [params.EDGE.values]
// 0 = 'Rising'
// 1 = 'Falling'
// 2 = 'Both'
//
// [params.POLARITY]
// mask = 'polarity'
// type = 'popup'
// [params.POLARITY.values]
// 0 = 'Active High'
// 1 = 'Active Low'
//
// [hdl_only]
//
// [mask_missing]
// x_in = 'icon drawing coordinate only'
// y_in = 'icon drawing coordinate only'
// x_out = 'icon drawing coordinate only'
// y_out = 'icon drawing coordinate only'
//
// [ports]
// [ports.renamed]
// din = 'in'
// dout = 'out'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module edge_detect #(
    /* EDGE: 0=rising, 1=falling, 2=both */
    parameter EDGE      = 0,
    /* POLARITY: 0=active high, 1=active low */
    parameter POLARITY   = 0
)(
    input  clk,
    input  din,
    output dout
);

localparam RISING   = 0;
localparam FALLING  = 1;
localparam BOTH     = 2;

// Power-on 0, as in Simulink (no X on the first cycle in 4-state simulators)
reg din_prev = 1'b0;

always @(posedge clk) begin
    din_prev <= din;
end

wire detect;
assign detect = (EDGE == RISING)  ? ( din & ~din_prev) :
                (EDGE == FALLING) ? (~din &  din_prev) :
                                         ( din ^  din_prev) ;

assign dout = (POLARITY == 0) ? detect : ~detect;

endmodule
