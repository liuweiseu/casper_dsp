module bus_replicate #(
    parameter int N_BITS      = 1,
    parameter int REPLICATION = 8,
    parameter int CSP_LATENCY = 4,
    parameter int MISC        = 1,
    parameter int MISC_WIDTH  = 1
)(
    input  clk,
    input  rst,
    input  [N_BITS-1:0]             in,
    input  [MISC_WIDTH-1:0]         misci,
    output [N_BITS*REPLICATION-1:0] out,
    output [MISC_WIDTH-1:0]         misco
);
    genvar i, s;

    generate
        if (CSP_LATENCY == 0) begin : gen_comb
            for (i = 0; i < REPLICATION; i++) begin : rep
                assign out[N_BITS*(i+1)-1 : N_BITS*i] = in;
            end
        end else begin : gen_pipe
            reg [N_BITS-1:0] pipe [0:CSP_LATENCY-1];

            always_ff @(posedge clk) begin
                if (rst) pipe[0] <= '0;
                else     pipe[0] <= in;
            end

            for (s = 1; s < CSP_LATENCY; s++) begin : stages
                always_ff @(posedge clk) begin
                    if (rst) pipe[s] <= '0;
                    else     pipe[s] <= pipe[s-1];
                end
            end

            for (i = 0; i < REPLICATION; i++) begin : rep
                assign out[N_BITS*(i+1)-1 : N_BITS*i] = pipe[CSP_LATENCY-1];
            end
        end
    endgenerate

    generate
        if (MISC == 0) begin : gen_no_misc
            assign misco = '0;
        end else if (CSP_LATENCY == 0) begin : gen_misc_comb
            assign misco = misci;
        end else begin : gen_misc_pipe
            reg [MISC_WIDTH-1:0] misc_pipe [0:CSP_LATENCY-1];

            always_ff @(posedge clk) begin
                if (rst) misc_pipe[0] <= '0;
                else     misc_pipe[0] <= misci;
            end

            for (s = 1; s < CSP_LATENCY; s++) begin : misc_stages
                always_ff @(posedge clk) begin
                    if (rst) misc_pipe[s] <= '0;
                    else     misc_pipe[s] <= misc_pipe[s-1];
                end
            end

            assign misco = misc_pipe[CSP_LATENCY-1];
        end
    endgenerate

endmodule
