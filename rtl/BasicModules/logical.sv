module logical #(
    parameter int NBITS   = 8,
    parameter int NINPUTS = 2,
    parameter int LATENCY = 1,
    /* FUNC: 0=AND, 1=NAND, 2=OR, 3=NOR, 4=XOR, 5=XNOR */
    parameter int FUNC    = 0
)(
    input  logic             clk,
    input  logic [NBITS-1:0] din [NINPUTS],
    output logic [NBITS-1:0] dout
);

    logic [NBITS-1:0] acc;
    logic [NBITS-1:0] result;

    always_comb begin
        acc = din[0];
        for (int i = 1; i < NINPUTS; i++) begin
            if      (FUNC == 0 || FUNC == 1) acc = acc & din[i];
            else if (FUNC == 2 || FUNC == 3) acc = acc | din[i];
            else                             acc = acc ^ din[i];
        end
        result = (FUNC == 1 || FUNC == 3 || FUNC == 5) ? ~acc : acc;
    end

    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign dout = result;
        end else begin : GEN_PIPE
            logic [NBITS-1:0] shift_reg [0:LATENCY-1];
            integer k;
            initial begin
                for (k = 0; k < LATENCY; k = k + 1)
                    shift_reg[k] = {NBITS{1'b0}};
            end
            always_ff @(posedge clk) begin
                shift_reg[0] <= result;
                for (k = 1; k < LATENCY; k = k + 1)
                    shift_reg[k] <= shift_reg[k-1];
            end
            assign dout = shift_reg[LATENCY-1];
        end
    endgenerate

endmodule
