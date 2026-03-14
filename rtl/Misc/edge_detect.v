module edge_detect #(
    /* EDGE_TYPE: 0=rising, 1=falling */
    parameter EDGE_TYPE = 0,
    /* OUTPUT_POL: 0=active high, 1=active low */
    parameter OUTPUT_POL = 0
)(
    input  clk,
    input  din,
    output dout
);

localparam RISING  = 0;
localparam FALLING = 1;

reg din_prev;
reg dout_reg;

always @(posedge clk) begin
    din_prev <= din;
    if (EDGE_TYPE == RISING)
        dout_reg <= din & ~din_prev;
    else
        dout_reg <= ~din & din_prev;
end

assign dout = (OUTPUT_POL == 0) ? dout_reg : ~dout_reg;

endmodule
