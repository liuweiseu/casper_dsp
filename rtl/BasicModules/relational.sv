module relational #(
    parameter int NBITS   = 8,
    /* COMP: 0=eq, 1=ne, 2=lt, 3=gt, 4=le, 5=ge */
    parameter int COMP    = 0,
    /* SIGNED: 0 = a and b are unsigned, 1 = a and b are two's complement */
    parameter int SIGNED  = 0,
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
        if (SIGNED != 0 && SIGNED != 1)
            $fatal(1, "Error: Invalid SIGNED = %0d. (0=unsigned, 1=signed)", SIGNED);
    end

    logic result;

    // Sign-extend by one bit so one comparison covers both cases
    logic signed [NBITS:0] a_x, b_x;
    assign a_x = {(SIGNED != 0) & a[NBITS-1], a};
    assign b_x = {(SIGNED != 0) & b[NBITS-1], b};

    always_comb begin
        case (COMP)
            0: result = (a_x == b_x);
            1: result = (a_x != b_x);
            2: result = (a_x <  b_x);
            3: result = (a_x >  b_x);
            4: result = (a_x <= b_x);
            5: result = (a_x >= b_x);
            default: result = 1'b0;
        endcase
    end

    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign out = result;
        end else begin : GEN_PIPE
            // Power-on value is given as a declaration initializer and the loop
            // variable is local to the always_ff: newer Verilator rejects a
            // variable written by both an 'initial' process and an always_ff
            // (MULTIDRIVEN).
            logic shift_reg [0:LATENCY-1] = '{default: '0};
            always_ff @(posedge clk) begin
                shift_reg[0] <= result;
                for (int k = 1; k < LATENCY; k = k + 1)
                    shift_reg[k] <= shift_reg[k-1];
            end
            assign out = shift_reg[LATENCY-1];
        end
    endgenerate

endmodule
