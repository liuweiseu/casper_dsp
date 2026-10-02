module ri_to_c #(
    parameter NBITS = 8
)(
    input  [NBITS-1:0] re,
    input  [NBITS-1:0] im,
    output [2*NBITS-1:0] c
);

assign c = {re, im};

endmodule
