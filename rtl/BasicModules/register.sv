module register #(
    /* BITWIDTH: data bit width */
    parameter BITWIDTH = 1
)(
    input  clk,
    input  rst,
    input  en,
    input  [BITWIDTH-1:0] d,
    output logic [BITWIDTH-1:0] q
);

always_ff @(posedge clk)
    if (rst)     q <= '0;
    else if (en) q <= d;

endmodule
