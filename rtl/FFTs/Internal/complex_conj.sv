// complex_conj — complex conjugate of N_INPUTS lanes
//
// Corresponds to casper_library's complex_conj (fixed point,
// complex_conj_init.m): the real part is delayed LATENCY cycles
// (real_delay), the imaginary part is negated by a bus_negate of the same
// width and binary point with latency LATENCY (Truncate, OVERFLOW 0 = Wrap,
// 1 = Saturate). With Wrap the most negative imaginary value stays as it is.
// Built from Delays/pipeline and Bus/negate.

module complex_conj #(
    parameter int N_INPUTS = 1,
    parameter int N_BITS   = 18,
    parameter int BIN_PT   = 17,
    parameter int LATENCY  = 1,
    parameter int OVERFLOW = 0
)(
    input  logic              clk,
    input  logic [N_BITS-1:0] din_re  [N_INPUTS],
    input  logic [N_BITS-1:0] din_im  [N_INPUTS],
    output logic [N_BITS-1:0] dout_re [N_INPUTS],
    output logic [N_BITS-1:0] dout_im [N_INPUTS]
);

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        pipeline #(.BITWIDTH(N_BITS), .LATENCY(LATENCY)) u_real_delay (
            .clk(clk), .din(din_re[n]), .dout(dout_re[n]));

        negate #(
            .N_BITS_IN(N_BITS), .BIN_PT_IN(BIN_PT), .TYPE_IN(1),
            .N_BITS_OUT(N_BITS), .BIN_PT_OUT(BIN_PT), .TYPE_OUT(1),
            .QUANTIZATION(0), .OVERFLOW(OVERFLOW), .LATENCY(LATENCY)
        ) u_imag_negate (.clk(clk), .din(din_im[n]), .dout(dout_im[n]));
    end

endmodule
