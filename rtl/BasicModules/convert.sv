// Matches xbsIndex_r4/Convert (Xilinx System Generator Type Converter),
// fixed-point output type only.
// Re-represents din from (N_BITS_IN, BIN_PT_IN) as (N_BITS_OUT, BIN_PT_OUT):
//   binary-point shift, then QUANTIZATION on the dropped LSBs
//   (0=Truncate, 1=Round unbiased +/-Inf i.e. ties away from zero,
//    2=Round unbiased even values i.e. ties to even), then OVERFLOW on the
//   excess MSBs (0=Wrap, 1=Saturate). "Flag as error" is not implemented.
// Boolean output type is N_BITS_OUT=1, BIN_PT_OUT=0, TYPE_OUT=0.
// ASYNC=1 adds the optional en port: en gates every pipeline stage;
//   ASYNC=0 ignores en and the pipeline is free-running.
module convert #(
    parameter int N_BITS_IN    = 37,
    parameter int BIN_PT_IN    = 35,
    parameter int TYPE_IN      = 1,  // 0 = Unsigned, 1 = Signed (2's comp)
    parameter int N_BITS_OUT   = 18,
    parameter int BIN_PT_OUT   = 17,
    parameter int TYPE_OUT     = 1,  // 0 = Unsigned, 1 = Signed (2's comp)
    parameter int QUANTIZATION = 0,  // 0 = Truncate, 1 = Round +/-Inf, 2 = Round even
    parameter int OVERFLOW     = 0,  // 0 = Wrap, 1 = Saturate
    parameter int ASYNC        = 0,  // 1 = en port active
    parameter int LATENCY      = 1   // 0 = combinational
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  en,
    input  logic [N_BITS_IN-1:0]  din,
    output logic [N_BITS_OUT-1:0] dout
);

    localparam int SHIFT  = BIN_PT_IN - BIN_PT_OUT;
    localparam int LSHIFT = (SHIFT < 0) ? -SHIFT : 0;
    // signed work domain: wide enough for an unsigned input, the rounding
    // carry, any left shift, and a safe saturation comparison
    localparam int WORK0  = N_BITS_IN + 2 + LSHIFT;
    localparam int WORK_W = (WORK0 > N_BITS_OUT + 2) ? WORK0 : N_BITS_OUT + 2;

    logic signed [WORK_W-1:0] din_ext;
    logic signed [WORK_W-1:0] shifted;
    logic        [N_BITS_OUT-1:0] result;

    assign din_ext = (TYPE_IN != 0)
                   ? {{(WORK_W-N_BITS_IN){din[N_BITS_IN-1]}}, din}
                   : {{(WORK_W-N_BITS_IN){1'b0}}, din};

    generate
        if (SHIFT > 0) begin : gen_shr
            if (QUANTIZATION == 1) begin : gen_round_inf
                // round to nearest, ties away from zero:
                // add half LSB (minus 1 when negative), then floor
                localparam logic signed [WORK_W-1:0] HALF = WORK_W'(1) <<< (SHIFT - 1);
                logic signed [WORK_W-1:0] rounded;
                assign rounded = din_ext
                               + (din_ext[WORK_W-1] ? HALF - WORK_W'(1) : HALF);
                assign shifted = rounded >>> SHIFT;
            end else if (QUANTIZATION == 2) begin : gen_round_even
                // round to nearest, ties to even result LSB
                localparam logic [SHIFT-1:0] HALF_REM = SHIFT'(1) << (SHIFT - 1);
                logic signed [WORK_W-1:0] trunc;
                logic        [SHIFT-1:0]  rem;
                assign trunc   = din_ext >>> SHIFT;
                assign rem     = din_ext[SHIFT-1:0];
                assign shifted = (rem > HALF_REM) ? trunc + WORK_W'(1) :
                                 (rem < HALF_REM) ? trunc :
                                 trunc + (trunc[0] ? WORK_W'(1) : WORK_W'(0));
            end else begin : gen_trunc
                assign shifted = din_ext >>> SHIFT;
            end
        end else begin : gen_shl
            assign shifted = din_ext <<< LSHIFT;
        end
    endgenerate

    generate
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
    endgenerate

    generate
        if (LATENCY == 0) begin : gen_comb
            assign dout = result;
        end else begin : gen_pipe
            logic ce;
            logic [N_BITS_OUT-1:0] pipe [0:LATENCY-1];

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

            assign dout = pipe[LATENCY-1];
        end
    endgenerate

endmodule
