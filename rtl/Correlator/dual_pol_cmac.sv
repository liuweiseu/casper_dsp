// dual_pol_cmac — casper_library dual-polarisation cmac
// (casper_library_correlator.slx, Block SID 814; mask initialization in
// system_root.xml, diagram in system_814.xml)
//
// Four cmacs, one per polarisation product (N = N_BITS_IN, m = N_BITS_OUT;
// slices count from the MSB):
//
//   cmac  (SID 858): a1[4N-1-:2N] (p0) · conj(a2[4N-1-:2N] (p0)), acc_in[8m-1-:2m] -> XX
//   cmac1 (SID 927): a1[2N-1-:2N] (p1) · conj(a2[2N-1-:2N] (p1)), acc_in[6m-1-:2m] -> YY
//   cmac2 (SID 855): a1 p0 · conj(a2 p1),                         acc_in[4m-1-:2m] -> XY
//   cmac3 (SID 856): a1 p1 · conj(a2 p0),                         acc_in[2m-1-:2m] -> YX
//   acc_out = {XX, YY, XY, YX}   (Concat, cmac first = MSBs)
//
// All four get the same sync. valid_in only goes to cmac3 (the others get
// a constant 0) and valid_out is cmac3's; the other valid outputs are
// terminated. Each cmac has its own sync->rst chain, as in the diagram.
//
// Mask initialization: bit_growth = ceil(log2(acc_len)),
// n_bits_out = 2*n_bits_in + 1 + bit_growth, and every cmac gets
// n_bits_a = n_bits_b = n_bits_in, bin_pt_a = bin_pt_b = n_bits_in - 1
// (so cmac's constraint A always holds), acc_len, mult/add_latency and
// multiplier_implementation. bin_pt_in is not passed on (bin_pt_out =
// 2*bin_pt_in is computed but unused): declared only.
//
// Parameters (mask names, stored defaults): ACC_LEN 128, N_BITS_IN 4,
// BIN_PT_IN 3, MULT_LATENCY 1, ADD_LATENCY 1, MULTIPLIER_IMPLEMENTATION 2
// (embedded multiplier core; resource only).
// Timing is that of cmac: acc_in -> acc_out and valid_in -> valid_out
// 2 cycles, dumps 2 cycles after each rst (sync + MULT + ADD + 1, then every
// ACC_LEN cycles).
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
// block = 'casper_library_correlator.slx/dual_pol_cmac'
// deviations = [
//   'BIN_PT_IN is declared only. It does nothing in Simulink either: the mask init computes bin_pt_out = 2*bin_pt_in but never uses it, and every cmac gets bin_pt = n_bits_in-1.',
// ]
//
// [params.MULTIPLIER_IMPLEMENTATION]
// mask = 'multiplier_implementation'
// type = 'popup'
// [params.MULTIPLIER_IMPLEMENTATION.values]
// 0 = 'behavioral HDL'
// 1 = 'standard core'
// 2 = 'embedded multiplier core'
//
// [hdl_only]
// N_BITS_OUT = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module dual_pol_cmac #(
    parameter int ACC_LEN                   = 128,
    parameter int N_BITS_IN                 = 4,
    parameter int BIN_PT_IN                 = 3,
    parameter int MULT_LATENCY              = 1,
    parameter int ADD_LATENCY               = 1,
    parameter int MULTIPLIER_IMPLEMENTATION = 2,
    // derived (mask initialization); not to be overridden
    parameter int N_BITS_OUT                = 2 * N_BITS_IN + 1 + $clog2(ACC_LEN)
)(
    input  logic                    clk,
    input  logic [4*N_BITS_IN-1:0]  a1,
    input  logic [4*N_BITS_IN-1:0]  a2,
    input  logic [8*N_BITS_OUT-1:0] acc_in,
    input  logic                    sync,
    input  logic                    valid_in,
    output logic [8*N_BITS_OUT-1:0] acc_out,
    output logic                    valid_out
);

    localparam int N = N_BITS_IN;
    localparam int M = N_BITS_OUT;

    initial begin
        if (N_BITS_OUT != 2 * N_BITS_IN + 1 + $clog2(ACC_LEN))
            $fatal(1, "dual_pol_cmac: N_BITS_OUT is derived, do not override");
    end

    logic [2*N-1:0] a1_p0, a1_p1, a2_p0, a2_p1;
    assign {a1_p0, a1_p1} = a1;
    assign {a2_p0, a2_p1} = a2;

    logic [2*M-1:0] xx, yy, xy, yx;

    cmac #(
        .ACC_LEN(ACC_LEN), .N_BITS_A(N), .BIN_PT_A(N - 1), .N_BITS_B(N), .BIN_PT_B(N - 1),
        .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
        .MULTIPLIER_IMPLEMENTATION(MULTIPLIER_IMPLEMENTATION)
    ) u_cmac (.clk(clk), .a(a1_p0), .b(a2_p0), .acc_in(acc_in[8*M-1 -: 2*M]),
              .sync(sync), .valid_in(1'b0), .acc_out(xx), .valid_out());

    cmac #(
        .ACC_LEN(ACC_LEN), .N_BITS_A(N), .BIN_PT_A(N - 1), .N_BITS_B(N), .BIN_PT_B(N - 1),
        .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
        .MULTIPLIER_IMPLEMENTATION(MULTIPLIER_IMPLEMENTATION)
    ) u_cmac1 (.clk(clk), .a(a1_p1), .b(a2_p1), .acc_in(acc_in[6*M-1 -: 2*M]),
               .sync(sync), .valid_in(1'b0), .acc_out(yy), .valid_out());

    cmac #(
        .ACC_LEN(ACC_LEN), .N_BITS_A(N), .BIN_PT_A(N - 1), .N_BITS_B(N), .BIN_PT_B(N - 1),
        .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
        .MULTIPLIER_IMPLEMENTATION(MULTIPLIER_IMPLEMENTATION)
    ) u_cmac2 (.clk(clk), .a(a1_p0), .b(a2_p1), .acc_in(acc_in[4*M-1 -: 2*M]),
               .sync(sync), .valid_in(1'b0), .acc_out(xy), .valid_out());

    cmac #(
        .ACC_LEN(ACC_LEN), .N_BITS_A(N), .BIN_PT_A(N - 1), .N_BITS_B(N), .BIN_PT_B(N - 1),
        .MULT_LATENCY(MULT_LATENCY), .ADD_LATENCY(ADD_LATENCY),
        .MULTIPLIER_IMPLEMENTATION(MULTIPLIER_IMPLEMENTATION)
    ) u_cmac3 (.clk(clk), .a(a1_p1), .b(a2_p0), .acc_in(acc_in[2*M-1 -: 2*M]),
               .sync(sync), .valid_in(valid_in), .acc_out(yx), .valid_out(valid_out));

    assign acc_out = {xx, yy, xy, yx};

endmodule
