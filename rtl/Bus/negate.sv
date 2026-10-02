// negate — two's-complement negation with output requantization
//
// dout = convert(-din)
//
// The negation is formed at full precision (N_BITS_IN + 1 bits, signed), so
// -(most negative input) and negated unsigned inputs are exact; the result is
// then requantized to the output format by a convert instance, which also
// provides the LATENCY pipeline. Corresponds to a single lane of
// casper_library's bus_negate (Xilinx Negate block).
//
// Encodings (common to all fixed-point modules in rtl/Bus/ and
// rtl/Multipliers/):
//   TYPE_*       : 0 = unsigned, 1 = signed
//   QUANTIZATION : 0 = truncate, 1 = round half away from zero,
//                  2 = round half to even
//   OVERFLOW     : 0 = wrap, 1 = saturate (2 = flag as error -> wrap)
//   LATENCY      : 0 = combinational, N > 0 = N register stages

module negate #(
    parameter int N_BITS_IN    = 8,
    parameter int BIN_PT_IN    = 4,
    parameter int TYPE_IN      = 1,
    parameter int N_BITS_OUT   = 8,
    parameter int BIN_PT_OUT   = 4,
    parameter int TYPE_OUT     = 1,
    parameter int QUANTIZATION = 0,
    parameter int OVERFLOW     = 0,
    parameter int LATENCY      = 1
)(
    input  logic                  clk,
    input  logic [N_BITS_IN-1:0]  din,
    output logic [N_BITS_OUT-1:0] dout
);

    localparam int N_BITS_FULL = N_BITS_IN + 1;

    logic signed [N_BITS_FULL-1:0] din_s;
    logic signed [N_BITS_FULL-1:0] neg;

    assign din_s = {(TYPE_IN != 0) ? din[N_BITS_IN-1] : 1'b0, din};
    assign neg   = -din_s;

    convert #(
        .N_BITS_IN (N_BITS_FULL), .BIN_PT_IN (BIN_PT_IN),  .TYPE_IN (1),
        .N_BITS_OUT(N_BITS_OUT),  .BIN_PT_OUT(BIN_PT_OUT), .TYPE_OUT(TYPE_OUT),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .LATENCY(LATENCY)
    ) u_convert (
        .clk (clk),
        .din (neg),
        .dout(dout)
    );

endmodule
