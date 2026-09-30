// convert_of — fixed-point convert with an overflow indication
//
// dout is exactly rtl/Bus/convert's output (signed in, signed out). of flags
// that the integer part of din does not fit the output format, using
// casper_library's convert_of rule (convert_of_init.m): with
//
//   wb_lost = (N_BITS_IN - BIN_PT_IN) - (N_BITS_OUT - BIN_PT_OUT)
//
// integer bits dropped, of = 1 when the top wb_lost+1 bits of din are not
// all equal (neither all 0 nor all 1), i.e. din is not a sign extension of a
// value that fits. The check looks at din only: a carry out of the rounding
// step (e.g. rounding the largest value up) is not flagged, as in
// casper_library. wb_lost <= 0 means overflow is impossible: of = 0.
// of and dout have the same LATENCY (pipeline stages power up to 0).
//
// Encodings as rtl/Bus/convert: QUANTIZATION 0=truncate, 1=round half away
// from zero, 2=round half to even; OVERFLOW 0=wrap, 1=saturate.

module convert_of #(
    parameter int N_BITS_IN    = 16,
    parameter int BIN_PT_IN    = 8,
    parameter int N_BITS_OUT   = 8,
    parameter int BIN_PT_OUT   = 4,
    parameter int QUANTIZATION = 0,
    parameter int OVERFLOW     = 0,
    parameter int LATENCY      = 0
)(
    input  logic                  clk,
    input  logic [N_BITS_IN-1:0]  din,
    output logic [N_BITS_OUT-1:0] dout,
    output logic                  of
);

    localparam int WB_LOST = (N_BITS_IN - BIN_PT_IN) - (N_BITS_OUT - BIN_PT_OUT);
    // number of top bits checked, clipped to the input width
    localparam int N_TOP   = (WB_LOST + 1 > N_BITS_IN) ? N_BITS_IN : WB_LOST + 1;

    convert #(
        .N_BITS_IN (N_BITS_IN),  .BIN_PT_IN (BIN_PT_IN),  .TYPE_IN (1),
        .N_BITS_OUT(N_BITS_OUT), .BIN_PT_OUT(BIN_PT_OUT), .TYPE_OUT(1),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .LATENCY(LATENCY)
    ) u_convert (
        .clk (clk),
        .din (din),
        .dout(dout)
    );

    logic of_raw;

    generate
        if (WB_LOST <= 0) begin : GEN_NEVER
            assign of_raw = 1'b0;
        end else begin : GEN_CHECK
            logic [N_TOP-1:0] top;
            assign top    = din[N_BITS_IN-1 -: N_TOP];
            assign of_raw = !((&top) || !(|top));
        end
    endgenerate

    pipeline #(.BITWIDTH(1), .LATENCY(LATENCY)) u_of_dly (
        .clk(clk), .din(of_raw), .dout(of));

endmodule
