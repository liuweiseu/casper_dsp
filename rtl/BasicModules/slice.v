module slice #(
    parameter NBITS = 8,
    parameter START_BIT = 0,
    parameter WIDTH = 1
)(
    input [NBITS-1: 0] din,
    output [WIDTH - 1 : 0] dout
);

assign dout = din[START_BIT + WIDTH - 1:START_BIT];

endmodule
