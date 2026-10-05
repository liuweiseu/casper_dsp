module multiplexer #(
    parameter int NBITS   = 8,
    parameter int NINPUTS = 2,
    /* LATENCY: 0 = combinational output, >=1 = pipeline stages */
    parameter int LATENCY = 1,
    /* USE_ENABLE: 1 = use the enable port en (Xilinx "Provide enable port"):
       en = 0 holds the pipeline registers; no effect when LATENCY = 0.
       en defaults to 1 and may be left unconnected when unused. */
    parameter int USE_ENABLE = 0
)(
    input  logic                             clk,
    input  logic                             en = 1'b1,
    input  logic [NBITS-1:0]                 din [NINPUTS],
    input  logic [$clog2(NINPUTS)-1:0]       sel,
    output logic [NBITS-1:0]                 dout
);

    logic [NBITS-1:0] result;

    always_comb begin
        result = din[sel];
    end

    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign dout = result;
        end else begin : GEN_PIPE
            // Power-on value is given as a declaration initializer and the loop
            // variable is local to the always_ff: newer Verilator rejects a
            // variable written by both an 'initial' process and an always_ff
            // (MULTIDRIVEN).
            logic [NBITS-1:0] shift_reg [0:LATENCY-1] = '{default: '0};
            always_ff @(posedge clk) if (USE_ENABLE == 0 || en) begin
                shift_reg[0] <= result;
                for (int k = 1; k < LATENCY; k = k + 1)
                    shift_reg[k] <= shift_reg[k-1];
            end
            assign dout = shift_reg[LATENCY-1];
        end
    endgenerate

endmodule
