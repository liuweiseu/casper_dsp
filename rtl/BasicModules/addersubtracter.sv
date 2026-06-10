// Matches xbsIndex_r4/AddSub (Xilinx System Generator Adder/Subtracter),
// Basic-tab options only: full-precision output, no quantization/overflow.
// c = a + b or a - b after binary-point alignment; output grows by 1 bit.
// MODE selects the operation: 0=Addition, 1=Subtraction, 2=Addition or
//   subtraction (runtime sub port: 0=add, 1=subtract).
// USE_CARRY_IN=1 enables cin: add computes a + b + cin, subtract computes
//   a - b - 1 + cin (a + ~b + cin, Xilinx c_addsub semantics).
// USE_CARRY_OUT=1 enables cout: the carry out of the result MSB (the
//   not-borrow flag for subtraction); otherwise cout is constant 0.
// ASYNC=1 adds the optional en port: en gates every pipeline stage;
//   ASYNC=0 ignores en and the pipeline is free-running.
module addersubtracter #(
    parameter int N_BITS_A      = 18,
    parameter int BIN_PT_A      = 17,
    parameter int TYPE_A        = 1,  // 0 = Unsigned, 1 = Signed (2's comp)
    parameter int N_BITS_B      = 18,
    parameter int BIN_PT_B      = 17,
    parameter int TYPE_B        = 1,
    parameter int MODE          = 0,  // 0 = Addition, 1 = Subtraction, 2 = Addition or subtraction
    parameter int USE_CARRY_IN  = 0,  // 1 = cin port active
    parameter int USE_CARRY_OUT = 0,  // 1 = cout port active
    parameter int ASYNC         = 0,  // 1 = en port active
    parameter int LATENCY       = 1   // 0 = combinational
)(
    input  logic                clk,
    input  logic                rst,
    input  logic                en,
    input  logic                sub,
    input  logic                cin,
    input  logic [N_BITS_A-1:0] a,
    input  logic [N_BITS_B-1:0] b,
    output logic [((N_BITS_A-BIN_PT_A > N_BITS_B-BIN_PT_B ? N_BITS_A-BIN_PT_A : N_BITS_B-BIN_PT_B)
                   + (BIN_PT_A > BIN_PT_B ? BIN_PT_A : BIN_PT_B) + 1)-1:0] c,
    output logic                cout
);

    // full-precision output format: aligned binary points, max integer
    // width, plus one growth bit
    localparam int BIN_PT_OUT = (BIN_PT_A > BIN_PT_B) ? BIN_PT_A : BIN_PT_B;
    localparam int INT_W      = (N_BITS_A - BIN_PT_A > N_BITS_B - BIN_PT_B)
                              ? N_BITS_A - BIN_PT_A : N_BITS_B - BIN_PT_B;
    localparam int OUT_W      = INT_W + BIN_PT_OUT + 1;
    localparam int SH_A       = BIN_PT_OUT - BIN_PT_A;
    localparam int SH_B       = BIN_PT_OUT - BIN_PT_B;

    // operands sign/zero-extended to OUT_W and aligned to BIN_PT_OUT
    logic [OUT_W-1:0] a_ow, b_ow, b_op;
    logic             do_sub, ci;
    logic [OUT_W:0]   sum;       // {carry, result}
    logic [OUT_W-1:0] c_comb;
    logic             cout_comb;

    assign a_ow = ((TYPE_A != 0) ? {{(OUT_W-N_BITS_A){a[N_BITS_A-1]}}, a}
                                 : {{(OUT_W-N_BITS_A){1'b0}}, a}) << SH_A;
    assign b_ow = ((TYPE_B != 0) ? {{(OUT_W-N_BITS_B){b[N_BITS_B-1]}}, b}
                                 : {{(OUT_W-N_BITS_B){1'b0}}, b}) << SH_B;

    assign do_sub = (MODE == 1) || (MODE == 2 && sub);
    assign b_op   = do_sub ? ~b_ow : b_ow;
    // without carry-in the subtract path needs +1 to complete a + ~b + 1
    assign ci     = (USE_CARRY_IN != 0) ? cin : do_sub;

    assign sum       = {1'b0, a_ow} + {1'b0, b_op} + {{OUT_W{1'b0}}, ci};
    assign c_comb    = sum[OUT_W-1:0];
    assign cout_comb = (USE_CARRY_OUT != 0) ? sum[OUT_W] : 1'b0;

    generate
        if (LATENCY == 0) begin : gen_comb
            assign c    = c_comb;
            assign cout = cout_comb;
        end else begin : gen_pipe
            logic ce;
            logic [OUT_W:0] pipe [0:LATENCY-1];   // {cout, c} bundled

            assign ce = (ASYNC == 0) ? 1'b1 : en;

            initial begin
                for (int i = 0; i < LATENCY; i++)
                    pipe[i] = '0;
            end

            always_ff @(posedge clk) begin
                if (rst)     pipe[0] <= '0;
                else if (ce) pipe[0] <= {cout_comb, c_comb};
            end

            for (genvar s = 1; s < LATENCY; s++) begin : stages
                always_ff @(posedge clk) begin
                    if (rst)     pipe[s] <= '0;
                    else if (ce) pipe[s] <= pipe[s-1];
                end
            end

            assign c    = pipe[LATENCY-1][OUT_W-1:0];
            assign cout = pipe[LATENCY-1][OUT_W];
        end
    endgenerate

endmodule
