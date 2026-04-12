module constant #(
    parameter int NBITS = 8,
    parameter int VAL   = 0
)(
    output logic [NBITS-1:0] out
);

    assign out = VAL[NBITS-1:0];

endmodule
