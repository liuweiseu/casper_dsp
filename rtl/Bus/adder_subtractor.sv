// adder_subtractor — fixed-point add / subtract with output requantization
//
// dout = convert(a + b)   (OPMODE = 0)
// dout = convert(a - b)   (OPMODE = 1)
//
// 'a' and 'b' have independent fixed-point formats. The sum/difference is
// first formed at full precision (exact: binary points aligned, one carry bit
// and one sign bit of growth), then requantized to the output format by a
// convert instance, which also provides the LATENCY pipeline. Corresponds to
// a single lane of casper_library's bus_addsub (Xilinx AddSub block).
//
// Encodings (common to all fixed-point modules in rtl/Bus/ and
// rtl/Multipliers/):
//   TYPE_*       : 0 = unsigned, 1 = signed
//   OPMODE       : 0 = addition, 1 = subtraction
//   QUANTIZATION : 0 = truncate, 1 = round half away from zero,
//                  2 = round half to even
//   OVERFLOW     : 0 = wrap, 1 = saturate (2 = flag as error -> wrap)
//   LATENCY      : 0 = combinational, N > 0 = N register stages
//
// Full-precision internal format (always signed):
//   BIN_PT_FULL = max(BIN_PT_A, BIN_PT_B)
//   N_BITS_FULL = max(N_BITS_A - BIN_PT_A, N_BITS_B - BIN_PT_B) + 2 + BIN_PT_FULL

module adder_subtractor #(
    parameter int N_BITS_A     = 8,
    parameter int BIN_PT_A     = 4,
    parameter int TYPE_A       = 1,
    parameter int N_BITS_B     = 8,
    parameter int BIN_PT_B     = 4,
    parameter int TYPE_B       = 1,
    parameter int N_BITS_OUT   = 9,
    parameter int BIN_PT_OUT   = 4,
    parameter int TYPE_OUT     = 1,
    parameter int OPMODE       = 0,
    parameter int QUANTIZATION = 0,
    parameter int OVERFLOW     = 0,
    parameter int LATENCY      = 1
)(
    input  logic                  clk,
    input  logic [N_BITS_A-1:0]   a,
    input  logic [N_BITS_B-1:0]   b,
    output logic [N_BITS_OUT-1:0] dout
);

    localparam int INT_A       = N_BITS_A - BIN_PT_A;
    localparam int INT_B       = N_BITS_B - BIN_PT_B;
    localparam int BIN_PT_FULL = (BIN_PT_A > BIN_PT_B) ? BIN_PT_A : BIN_PT_B;
    localparam int INT_FULL    = ((INT_A > INT_B) ? INT_A : INT_B) + 2;
    localparam int N_BITS_FULL = INT_FULL + BIN_PT_FULL;

    logic signed [N_BITS_FULL-1:0] a_full;
    logic signed [N_BITS_FULL-1:0] b_full;
    logic signed [N_BITS_FULL-1:0] full;

    // ── align both operands to the full-precision format ─────────────────────
    convert #(
        .N_BITS_IN (N_BITS_A),    .BIN_PT_IN (BIN_PT_A),    .TYPE_IN (TYPE_A),
        .N_BITS_OUT(N_BITS_FULL), .BIN_PT_OUT(BIN_PT_FULL), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(0)
    ) u_align_a (
        .clk (clk),
        .din (a),
        .dout(a_full)
    );

    convert #(
        .N_BITS_IN (N_BITS_B),    .BIN_PT_IN (BIN_PT_B),    .TYPE_IN (TYPE_B),
        .N_BITS_OUT(N_BITS_FULL), .BIN_PT_OUT(BIN_PT_FULL), .TYPE_OUT(1),
        .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(0)
    ) u_align_b (
        .clk (clk),
        .din (b),
        .dout(b_full)
    );

    // ── full-precision add / subtract (cannot overflow N_BITS_FULL) ──────────
    generate
        if (OPMODE == 0) begin : GEN_ADD
            assign full = a_full + b_full;
        end else begin : GEN_SUB
            assign full = a_full - b_full;
        end
    endgenerate

    // ── requantize to the output format + pipeline ───────────────────────────
    convert #(
        .N_BITS_IN (N_BITS_FULL), .BIN_PT_IN (BIN_PT_FULL), .TYPE_IN (1),
        .N_BITS_OUT(N_BITS_OUT),  .BIN_PT_OUT(BIN_PT_OUT),  .TYPE_OUT(TYPE_OUT),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .LATENCY(LATENCY)
    ) u_convert (
        .clk (clk),
        .din (full),
        .dout(dout)
    );

endmodule
