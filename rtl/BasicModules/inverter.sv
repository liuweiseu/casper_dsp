module inverter #(
    parameter int NBITS   = 8,
    /* LATENCY: 0 = combinational output, >=1 = pipeline stages */
    parameter int LATENCY = 0
)(
    input  logic             clk,
    input  logic [NBITS-1:0] din,
    output logic [NBITS-1:0] dout
);

    logic [NBITS-1:0] result;
    assign result = ~din;

    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign dout = result;
        end else begin : GEN_PIPE
            // Power-on value is given as a declaration initializer and the loop
            // variable is local to the always_ff: newer Verilator rejects a
            // variable written by both an 'initial' process and an always_ff
            // (MULTIDRIVEN).
            logic [NBITS-1:0] shift_reg [0:LATENCY-1] = '{default: '0};
            always_ff @(posedge clk) begin
                shift_reg[0] <= result;
                for (int k = 1; k < LATENCY; k = k + 1)
                    shift_reg[k] <= shift_reg[k-1];
            end
            assign dout = shift_reg[LATENCY-1];
        end
    endgenerate

endmodule
