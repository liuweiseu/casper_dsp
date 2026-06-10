// Matches xbsIndex_r4/Mult (Xilinx System Generator Multiplier).
// Fixed-point multiplier p = a * b with LATENCY pipeline stages.
// PRECISION=0 (Full): output is N_BITS_A+N_BITS_B bits at BIN_PT_A+BIN_PT_B,
//   no quantization/overflow logic.
// PRECISION=1 (User defined): output is N_BITS_OUT bits at BIN_PT_OUT with
//   QUANTIZATION (0=Truncate, 1=Round unbiased +/-Inf) and
//   OVERFLOW (0=Wrap, 1=Saturate) applied. "Flag as error" is not implemented.
// ASYNC=1 adds the optional en port: en gates every pipeline stage (clock
//   enable); ASYNC=0 ignores en and the pipeline is free-running.
module multiplier #(
    parameter int N_BITS_A     = 18,
    parameter int BIN_PT_A     = 17,
    parameter int N_BITS_B     = 18,
    parameter int BIN_PT_B     = 17,
    parameter int TYPE_A       = 1,  // 0 = Unsigned, 1 = Signed (2's comp)
    parameter int TYPE_B       = 1,
    parameter int PRECISION    = 0,  // 0 = Full, 1 = User defined
    parameter int N_BITS_OUT   = 36, // PRECISION=1 only
    parameter int BIN_PT_OUT   = 34, // PRECISION=1 only
    parameter int TYPE_OUT     = 1,  // PRECISION=1 only: 0 = Unsigned, 1 = Signed
    parameter int QUANTIZATION = 0,  // 0 = Truncate, 1 = Round (unbiased: +/- Inf)
    parameter int OVERFLOW     = 0,  // 0 = Wrap, 1 = Saturate
    parameter int ASYNC        = 0,  // 1 = en port active
    parameter int LATENCY      = 2   // 0 = combinational
)(
    input  logic                clk,
    input  logic                rst,
    input  logic                en,
    input  logic [N_BITS_A-1:0] a,
    input  logic [N_BITS_B-1:0] b,
    output logic [((PRECISION == 0) ? N_BITS_A + N_BITS_B : N_BITS_OUT)-1:0] p
);

    localparam int FULL_W = N_BITS_A + N_BITS_B;
    localparam int OUT_W  = (PRECISION == 0) ? FULL_W : N_BITS_OUT;

    // full-precision product, computed in a signed domain wide enough to
    // hold any signed/unsigned operand combination exactly
    localparam int PROD_W = FULL_W + 2;

    logic signed [N_BITS_A:0]  a_s;
    logic signed [N_BITS_B:0]  b_s;
    logic signed [PROD_W-1:0]  prod;
    logic        [OUT_W-1:0]   result;

    assign a_s  = (TYPE_A != 0) ? {a[N_BITS_A-1], a} : {1'b0, a};
    assign b_s  = (TYPE_B != 0) ? {b[N_BITS_B-1], b} : {1'b0, b};
    assign prod = a_s * b_s;

    generate
        if (PRECISION == 0) begin : gen_full
            assign result = prod[OUT_W-1:0];
        end else begin : gen_user
            localparam int SHIFT  = (BIN_PT_A + BIN_PT_B) - BIN_PT_OUT;
            localparam int LSHIFT = (SHIFT < 0) ? -SHIFT : 0;
            localparam int WORK0  = PROD_W + 1 + LSHIFT;
            localparam int WORK_W = (WORK0 > N_BITS_OUT + 2) ? WORK0 : N_BITS_OUT + 2;

            logic signed [WORK_W-1:0] shifted;

            if (SHIFT > 0) begin : gen_shr
                if (QUANTIZATION == 1) begin : gen_round
                    // round to nearest, ties away from zero:
                    // add half LSB (minus 1 when negative), then floor
                    localparam logic signed [WORK_W-1:0] HALF = WORK_W'(1) <<< (SHIFT - 1);
                    logic signed [WORK_W-1:0] rounded;
                    assign rounded = WORK_W'(prod)
                                   + (prod[PROD_W-1] ? HALF - WORK_W'(1) : HALF);
                    assign shifted = rounded >>> SHIFT;
                end else begin : gen_trunc
                    assign shifted = WORK_W'(prod) >>> SHIFT;
                end
            end else begin : gen_shl
                assign shifted = WORK_W'(prod) <<< LSHIFT;
            end

            if (OVERFLOW == 0) begin : gen_wrap
                assign result = shifted[N_BITS_OUT-1:0];
            end else if (TYPE_OUT != 0) begin : gen_sat_signed
                localparam logic signed [WORK_W-1:0] SMAX = (WORK_W'(1) <<< (N_BITS_OUT - 1)) - 1;
                localparam logic signed [WORK_W-1:0] SMIN = -(WORK_W'(1) <<< (N_BITS_OUT - 1));
                assign result = (shifted > SMAX) ? SMAX[N_BITS_OUT-1:0] :
                                (shifted < SMIN) ? SMIN[N_BITS_OUT-1:0] :
                                                   shifted[N_BITS_OUT-1:0];
            end else begin : gen_sat_unsigned
                localparam logic signed [WORK_W-1:0] UMAX = (WORK_W'(1) <<< N_BITS_OUT) - 1;
                assign result = (shifted < 0)    ? {N_BITS_OUT{1'b0}} :
                                (shifted > UMAX) ? UMAX[N_BITS_OUT-1:0] :
                                                   shifted[N_BITS_OUT-1:0];
            end
        end
    endgenerate

    generate
        if (LATENCY == 0) begin : gen_comb
            assign p = result;
        end else begin : gen_pipe
            logic ce;
            logic [OUT_W-1:0] pipe [0:LATENCY-1];

            assign ce = (ASYNC == 0) ? 1'b1 : en;

            initial begin
                for (int i = 0; i < LATENCY; i++)
                    pipe[i] = '0;
            end

            always_ff @(posedge clk) begin
                if (rst)     pipe[0] <= '0;
                else if (ce) pipe[0] <= result;
            end

            for (genvar s = 1; s < LATENCY; s++) begin : stages
                always_ff @(posedge clk) begin
                    if (rst)     pipe[s] <= '0;
                    else if (ce) pipe[s] <= pipe[s-1];
                end
            end

            assign p = pipe[LATENCY-1];
        end
    endgenerate

endmodule
