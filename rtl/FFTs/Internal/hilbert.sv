// hilbert — split the FFT of two real signals packed as one complex signal
//
// Corresponds to casper_library's hilbert (fixed point, misc off,
// hilbert_init.m). For each of the N_INPUTS lanes, with a = Z[k] and
// b = Z[N-k] of z = x + j·y:
//
//   even = (a + conj(b)) / 2     = X[k]
//   odd  = (a − conj(b)) / (2j)  = Y[k]
//
//   even_re = (a_re + b_re) / 2      odd_re = (a_im + b_im) / 2
//   even_im = (a_im − b_im) / 2      odd_im = (b_re − a_re) / 2
//
// The four sums are full precision (BIT_WIDTH+1 bits, bus_addsub with
// latency ADD_LATENCY); the division by 2 is bus_scale(-1), i.e. the binary
// point moves to BIN_PT_IN+1, and bus_convert brings them back to
// BIT_WIDTH bits / BIN_PT_IN with round-half-even and wrap (fixed in
// hilbert_init.m), latency CONV_LATENCY. All values are signed.
// Built from Bus/adder_subtractor and Bus/convert.
//
// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'casper_library_ffts_internal.slx/hilbert'
// deviations = [
//   "misc='on' (misci/misco, delayed by add_latency+conv_latency in hilbert_init.m) is not implemented: the HDL has no MISC parameter",
//   "floating_point='on' builds a different datapath in Simulink (no bus_scale/bus_convert, hilbert_init.m floating branch); the HDL implements only the fixed-point path (full-precision BIT_WIDTH+1 add/sub, /2 by binary-point shift, convert to BIT_WIDTH with Round (unbiased: Even Values) + Wrap, as hilbert_init.m bus_convert 'quantization','2','overflow','0')",
//   'test vectors in casper_dsp/test_data/FFTs/Internal/hilbert/test_data.md come from a Python reference model (not exported from MATLAB), so cycle/bit equivalence with the Simulink block is unverified',
// ]
//
// [hdl_only]
//
// [mask_missing]
// misc = 'misc pass-through (misci/misco ports) is not implemented'
// floating_point = 'floating point is not implemented'
// float_type = 'floating point is not implemented'
// exp_width = 'floating point is not implemented'
// frac_width = 'floating point is not implemented'
//
// [ports]
// note = 'each Simulink complex port x is split into x_re / x_im'
// [ports.renamed]
// [ports.missing]
// misci = 'misc=on only (not implemented)'
// misco = 'misc=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module hilbert #(
    parameter int N_INPUTS     = 1,
    parameter int BIT_WIDTH    = 18,
    parameter int BIN_PT_IN    = 17,
    parameter int ADD_LATENCY  = 1,
    parameter int CONV_LATENCY = 1
)(
    input  logic                 clk,
    input  logic [BIT_WIDTH-1:0] a_re    [N_INPUTS],
    input  logic [BIT_WIDTH-1:0] a_im    [N_INPUTS],
    input  logic [BIT_WIDTH-1:0] b_re    [N_INPUTS],
    input  logic [BIT_WIDTH-1:0] b_im    [N_INPUTS],
    output logic [BIT_WIDTH-1:0] even_re [N_INPUTS],
    output logic [BIT_WIDTH-1:0] even_im [N_INPUTS],
    output logic [BIT_WIDTH-1:0] odd_re  [N_INPUTS],
    output logic [BIT_WIDTH-1:0] odd_im  [N_INPUTS]
);

    localparam int BW = BIT_WIDTH;

    for (genvar n = 0; n < N_INPUTS; n++) begin : GEN_LANE
        // casper order: add_even_real, sub_odd_imag, sub_even_imag, add_odd_real
        logic [BW-1:0] op_a [4], op_b [4], res [4];
        logic [BW:0]   sum  [4];

        assign op_a = '{a_re[n], b_re[n], a_im[n], a_im[n]};
        assign op_b = '{b_re[n], a_re[n], b_im[n], b_im[n]};

        for (genvar i = 0; i < 4; i++) begin : GEN_OP
            adder_subtractor #(
                .N_BITS_A(BW), .BIN_PT_A(BIN_PT_IN), .TYPE_A(1),
                .N_BITS_B(BW), .BIN_PT_B(BIN_PT_IN), .TYPE_B(1),
                .N_BITS_OUT(BW + 1), .BIN_PT_OUT(BIN_PT_IN), .TYPE_OUT(1),
                .OPMODE((i == 1 || i == 2) ? 1 : 0), .QUANTIZATION(0), .OVERFLOW(0),
                .CSP_LATENCY(ADD_LATENCY)
            ) u_addsub (.clk(clk), .a(op_a[i]), .b(op_b[i]), .dout(sum[i]));

            // bus_scale(-1) reinterprets sum with BIN_PT_IN+1, then bus_convert
            convert #(
                .N_BITS_IN(BW + 1), .BIN_PT_IN(BIN_PT_IN + 1), .TYPE_IN(1),
                .N_BITS_OUT(BW), .BIN_PT_OUT(BIN_PT_IN), .TYPE_OUT(1),
                .QUANTIZATION(2), .OVERFLOW(0), .CSP_LATENCY(CONV_LATENCY)
            ) u_convert (.clk(clk), .din(sum[i]), .dout(res[i]));
        end

        // ri_to_c: even = (res0, res2), odd = (res3, res1)
        assign even_re[n] = res[0];
        assign even_im[n] = res[2];
        assign odd_re[n]  = res[3];
        assign odd_im[n]  = res[1];
    end

endmodule
