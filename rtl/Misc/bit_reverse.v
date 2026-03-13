module bit_reverse #(
    parameter NBITS = 8
)(
    input  [NBITS-1:0] din,
    output [NBITS-1:0] dout
);

genvar i;
generate
    for (i = 0; i < NBITS; i = i + 1) begin : GEN_REVERSE
        assign dout[i] = din[NBITS-1-i];
    end
endgenerate

endmodule
