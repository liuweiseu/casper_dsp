// simple_bram_vacc — casper_library_accumulators/simple_bram_vacc: vector
// accumulator over VEC_LEN-sample vectors in a delay_bram
//
// Structure of the block (simple_bram_vacc_init.m only sets the types):
//   pulse_ext (pulse_len = VEC_LEN) on new_acc        -> valid, Mux select
//   Mux: sel = 0 -> delay_bram output, sel = 1 -> 0   (latency 0)
//   Adder: din + Mux, User Defined <ARITH_TYPE> N_BITS_BIN_PT, Truncate /
//          Wrap, latency 2
//   delay_bram (DelayLen = VEC_LEN - 2, bram_latency 2) on the Adder output
//                                                     -> dout
// The adder and the delay_bram form a VEC_LEN-cycle loop, so each sample adds
// to the sum of the same vector position; while valid = 1 (the VEC_LEN
// cycles after a rising edge of new_acc, and the first VEC_LEN cycles after
// power-on) the loop restarts from 0, and dout shows the finished sums. dout
// is the delay_bram output: a sum leaves the loop VEC_LEN cycles after its
// last sample entered the adder.
//
// din has its own fixed-point type (N_BITS_IN, BIN_PT_IN, TYPE_IN; inherited
// in Simulink); the adder aligns its binary point with BIN_PT and truncates /
// wraps to the output type.
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
// block = 'casper_library_accumulators.slx/simple_bram_vacc'
// deviations = [
//   'simple_bram_vacc_init.m only shows an error dialog for vec_len < 6, n_bits < 1 or bin_pt > n_bits and builds the block anyway (vec_len < 6 then fails in delay_bram, docs/bugs.md bug 7); the HDL stops with $fatal.',
// ]
//
// [params.VEC_LEN]
// mask = 'vec_len'
// type = 'edit'
//
// [params.ARITH_TYPE]
// mask = 'arith_type'
// type = 'popup'
// [params.ARITH_TYPE.values]
// 0 = 'Unsigned'
// 1 = 'Signed'
//
// [params.N_BITS]
// mask = 'n_bits'
// type = 'edit'
//
// [params.BIN_PT]
// mask = 'bin_pt'
// type = 'edit'
//
// [hdl_only]
// N_BITS_IN = 'inherited din width'
// BIN_PT_IN = 'inherited din binary point'
// TYPE_IN = 'inherited din signedness (0 unsigned, 1 signed)'
// PLATFORM = 'implementation: memory vendor of the delay_bram (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
//
// [ports]
// order = 'Simulink: new_acc, din -> dout, valid; HDL: clk, new_acc, din -> dout, valid'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module simple_bram_vacc #(
    parameter int    VEC_LEN    = 16,
    parameter int    ARITH_TYPE = 0,      // 0 Unsigned, 1 Signed (output / accumulator)
    parameter int    N_BITS     = 32,
    parameter int    BIN_PT     = 0,
    parameter int    N_BITS_IN  = 8,      // din type (inherited in Simulink)
    parameter int    BIN_PT_IN  = 0,
    parameter int    TYPE_IN    = 0,
    parameter string PLATFORM   = "GENERIC"
)(
    input  logic                 clk,
    input  logic                 new_acc,
    input  logic [N_BITS_IN-1:0] din,
    output logic [N_BITS-1:0]    dout,
    output logic                 valid
);

    initial
    begin
        if (VEC_LEN < 6)
            $fatal(1, "simple_bram_vacc: VEC_LEN = %0d must be greater than 5", VEC_LEN);
        if (N_BITS < 1)
            $fatal(1, "simple_bram_vacc: N_BITS = %0d must be greater than 0", N_BITS);
        if (BIN_PT > N_BITS)
            $fatal(1, "simple_bram_vacc: BIN_PT = %0d cannot be greater than N_BITS = %0d", BIN_PT, N_BITS);
        if (ARITH_TYPE != 0 && ARITH_TYPE != 1)
            $fatal(1, "simple_bram_vacc: invalid ARITH_TYPE = %0d (0 Unsigned, 1 Signed)", ARITH_TYPE);
    end

    logic [N_BITS-1:0] zero, fb, mux_out, sum;
    logic [N_BITS-1:0] mux_in [2];

    pulse_ext #(.PULSE_LEN(VEC_LEN)) u_pulse_ext (.clk(clk), .in(new_acc), .out(valid));

    // the Simulink Constant 0 (BasicModules constant takes an int VAL, at
    // most 32 bits, while N_BITS can be wider)
    assign zero = '0;

    assign mux_in = '{fb, zero};          // d0: feedback, d1: restart from 0
    multiplexer #(.NBITS(N_BITS), .NINPUTS(2), .LATENCY(0)) u_mux (
        .clk(clk), .din(mux_in), .sel(valid), .dout(mux_out));

    adder_subtractor #(
        .N_BITS_A(N_BITS_IN), .BIN_PT_A(BIN_PT_IN), .TYPE_A(TYPE_IN),
        .N_BITS_B(N_BITS),    .BIN_PT_B(BIN_PT),    .TYPE_B(ARITH_TYPE),
        .N_BITS_OUT(N_BITS),  .BIN_PT_OUT(BIN_PT),  .TYPE_OUT(ARITH_TYPE),
        .OPMODE(0), .QUANTIZATION(0), .OVERFLOW(0), .CSP_LATENCY(2)
    ) u_adder (.clk(clk), .a(din), .b(mux_out), .dout(sum), .misco(), .dvalid());

    delay_bram #(.BITWIDTH(N_BITS), .DELAY_LEN(VEC_LEN - 2), .BRAM_LATENCY(2), .PLATFORM(PLATFORM)) u_delay_bram (
        .clk(clk), .din(sum), .dout(fb));

    assign dout = fb;

endmodule
