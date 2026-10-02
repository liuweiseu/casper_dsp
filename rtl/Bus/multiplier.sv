// multiplier — fixed-point real multiply with output requantization
//
// dout = convert(a * b)
//
// 'a' and 'b' have independent fixed-point formats. The product is formed at
// full precision (exact), then requantized to the output format by a convert
// instance, which also provides the LATENCY pipeline. Corresponds to a single
// real lane of casper_library's bus_mult (Xilinx Mult block).
//
// Encodings (common to all fixed-point modules in rtl/Bus/ and
// rtl/Multipliers/):
//   TYPE_*       : 0 = unsigned, 1 = signed
//   QUANTIZATION : 0 = truncate, 1 = round half away from zero,
//                  2 = round half to even
//   OVERFLOW     : 0 = wrap, 1 = saturate (2 = flag as error -> wrap)
//   LATENCY      : 0 = combinational, N > 0 = N register stages
//
// Full-precision internal format (always signed):
//   N_BITS_FULL = N_BITS_A + N_BITS_B + 2    (operands widened by 1 sign bit each)
//   BIN_PT_FULL = BIN_PT_A + BIN_PT_B

module multiplier #(
    parameter int N_BITS_A     = 8,
    parameter int BIN_PT_A     = 7,
    parameter int TYPE_A       = 1,
    parameter int N_BITS_B     = 8,
    parameter int BIN_PT_B     = 7,
    parameter int TYPE_B       = 1,
    parameter int N_BITS_OUT   = 16,
    parameter int BIN_PT_OUT   = 14,
    parameter int TYPE_OUT     = 1,
    parameter int QUANTIZATION = 0,
    parameter int OVERFLOW     = 0,
    parameter int LATENCY      = 1
)(
    input  logic                  clk,
    input  logic [N_BITS_A-1:0]   a,
    input  logic [N_BITS_B-1:0]   b,
    output logic [N_BITS_OUT-1:0] dout
);

    localparam int N_BITS_FULL = N_BITS_A + N_BITS_B + 2;
    localparam int BIN_PT_FULL = BIN_PT_A + BIN_PT_B;

    logic signed [N_BITS_A:0]      a_s;   // a as a signed (N_BITS_A+1)-bit integer
    logic signed [N_BITS_B:0]      b_s;
    logic signed [N_BITS_FULL-1:0] full;

    assign a_s = {(TYPE_A != 0) ? a[N_BITS_A-1] : 1'b0, a};
    assign b_s = {(TYPE_B != 0) ? b[N_BITS_B-1] : 1'b0, b};

    // ── full-precision product ───────────────────────────────────────────────
    assign full = N_BITS_FULL'(a_s) * N_BITS_FULL'(b_s);

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
