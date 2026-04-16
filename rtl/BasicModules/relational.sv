module relational #(
    parameter int NBITS   = 8,
    /* COMP: 0=eq, 1=ne, 2=lt, 3=gt, 4=le, 5=ge (unsigned comparison) */
    parameter int COMP    = 0,
    /* LATENCY: 0 = combinational output, >=1 = pipeline stages */
    parameter int LATENCY = 1
)(
    input  logic             clk,
    input  logic [NBITS-1:0] a,
    input  logic [NBITS-1:0] b,
    output logic             out
);

    initial begin
        if (COMP < 0 || COMP > 5)
            $fatal(1, "Error: Invalid COMP = %0d. (0=eq,1=ne,2=lt,3=gt,4=le,5=ge)", COMP);
    end

    logic result;

    always_comb begin
        case (COMP)
            0: result = (a == b);
            1: result = (a != b);
            2: result = (a <  b);
            3: result = (a >  b);
            4: result = (a <= b);
            5: result = (a >= b);
            default: result = 1'b0;
        endcase
    end

    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign out = result;
        end else begin : GEN_PIPE
            logic shift_reg [0:LATENCY-1];
            integer k;
            initial begin
                for (k = 0; k < LATENCY; k = k + 1)
                    shift_reg[k] = 1'b0;
            end
            always_ff @(posedge clk) begin
                shift_reg[0] <= result;
                for (k = 1; k < LATENCY; k = k + 1)
                    shift_reg[k] <= shift_reg[k-1];
            end
            assign out = shift_reg[LATENCY-1];
        end
    endgenerate

endmodule
