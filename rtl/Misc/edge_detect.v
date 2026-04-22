module edge_detect #(
    /* EDGE_TYPE: 0=rising, 1=falling, 2=both */
    parameter EDGE_TYPE = 0,
    /* OUTPUT_POL: 0=active high, 1=active low */
    parameter OUTPUT_POL = 0
)(
    input  clk,
    input  din,
    output dout
);

localparam RISING   = 0;
localparam FALLING  = 1;
localparam BOTH     = 2;

reg din_prev;

always @(posedge clk) begin
    din_prev <= din;
end

wire detect;
assign detect = (EDGE_TYPE == RISING)  ? ( din & ~din_prev) :
                (EDGE_TYPE == FALLING) ? (~din &  din_prev) :
                                         ( din ^   din_prev);

assign dout = (OUTPUT_POL == 0) ? detect : ~detect;

endmodule
