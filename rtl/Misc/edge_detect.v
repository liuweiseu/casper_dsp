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

// Power-on 0, as in Simulink (no X on the first cycle in 4-state simulators)
reg din_prev = 1'b0;

always @(posedge clk) begin
    din_prev <= din;
end

wire detect;
assign detect = (EDGE_TYPE == RISING)  ? ( din & ~din_prev) :
                (EDGE_TYPE == FALLING) ? (~din &  din_prev) :
                                         ( din ^  din_prev) ;

assign dout = (OUTPUT_POL == 0) ? detect : ~detect;

endmodule
