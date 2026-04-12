module register #(
    /* BITWIDTH: data bit width */
    parameter BITWIDTH   = 1,
    /* USE_RST: 1 = use synchronous reset (rst pin active), 0 = no reset pin */
    parameter USE_RST    = 1,
    /* USE_ENABLE: 1 = use enable (en pin active), 0 = no enable pin */
    parameter USE_ENABLE = 1,
    /* INIT_VAL: value loaded into q when rst is asserted */
    parameter INIT_VAL   = 0
)(
    input  clk,
    input  rst,
    input  en,
    input  [BITWIDTH-1:0] d,
    output logic [BITWIDTH-1:0] q
);

initial q = INIT_VAL[BITWIDTH-1:0];

generate
    if (USE_RST && USE_ENABLE) begin
        always_ff @(posedge clk)
            if (rst)     q <= INIT_VAL[BITWIDTH-1:0];
            else if (en) q <= d;
    end else if (USE_RST && !USE_ENABLE) begin
        always_ff @(posedge clk)
            if (rst) q <= INIT_VAL[BITWIDTH-1:0];
            else     q <= d;
    end else if (!USE_RST && USE_ENABLE) begin
        always_ff @(posedge clk)
            if (en) q <= d;
    end else begin
        always_ff @(posedge clk)
            q <= d;
    end
endgenerate

endmodule
