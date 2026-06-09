module ri_to_c #(
    parameter RE_WIDTH = 8,
    parameter IM_WIDTH = 8
)(
    input  [RE_WIDTH-1:0] re,
    input  [IM_WIDTH-1:0] im,
    output [RE_WIDTH+IM_WIDTH-1:0] c
);

assign c = {re, im};

endmodule
