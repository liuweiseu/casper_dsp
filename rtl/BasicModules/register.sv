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
    // Power-on value is given as a declaration initializer rather than an
    // 'initial' block: newer Verilator rejects a variable written by both an
    // 'initial' process and an always_ff (MULTIDRIVEN).
    output logic [BITWIDTH-1:0] q = BITWIDTH'(INIT_VAL)
);

generate
    if (USE_RST && USE_ENABLE) begin
        always_ff @(posedge clk)
            if (rst)     q <= BITWIDTH'(INIT_VAL);
            else if (en) q <= d;
    end else if (USE_RST && !USE_ENABLE) begin
        always_ff @(posedge clk)
            if (rst) q <= BITWIDTH'(INIT_VAL);
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
