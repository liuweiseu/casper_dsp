module c_to_ri #(
    parameter NBITS  = 8,
    parameter BIN_PT = 7
)(
    input  [2*NBITS-1:0] c,
    output [NBITS-1:0] re,
    output [NBITS-1:0] im
);

assign re = c[2*NBITS-1:NBITS];
assign im = c[NBITS-1:0];

endmodule
