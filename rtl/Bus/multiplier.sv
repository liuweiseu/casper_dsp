// multiplier — fixed-point real multiply with output requantization
//
// dout = convert(a * b)
//
// 'a' and 'b' have independent fixed-point formats. The product is formed at
// full precision (exact), then requantized to the output format by a convert
// instance, which also provides the MULT_LATENCY pipeline. Corresponds to a single
// real lane of casper_library's bus_mult (Xilinx Mult block).
//
// Encodings (common to all fixed-point modules in rtl/Bus/ and
// rtl/Multipliers/):
//   TYPE_*       : 0 = unsigned, 1 = signed
//   QUANTIZATION : 0 = truncate, 1 = round half away from zero,
//                  2 = round half to even
//   OVERFLOW     : 0 = wrap, 1 = saturate (2 = flag as error -> wrap)
//   MULT_LATENCY      : 0 = combinational, N > 0 = N register stages
//
// Full-precision internal format (always signed):
//   N_BITS_FULL = N_BITS_A + N_BITS_B + 2    (operands widened by 1 sign bit each)
//   BIN_PT_FULL = BIN_PT_A + BIN_PT_B
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
// block = 'casper_library_bus.slx/bus_mult'
// deviations = [
//   "Latency: Simulink's real-lane latency is fan_latency (bus_replicate, bus_mult_init.m:377) + mult_latency (xbsIndex_r4/Mult, :684). The HDL has only MULT_LATENCY, so it matches only when fan_latency=0 (the mask default).",
//   "QUANTIZATION=2 has no Simulink counterpart: bus_mult_init.m:639-640 passes 'Round  (unbiased: Even Values)' to xbsIndex_r4/Mult, whose quantization popup offers only 'Truncate' and 'Round  (unbiased: +/- Inf)'.",
//   "OVERFLOW=2 is mapped to the Mult 'Flag as error' mode (bus_mult_init.m:647), where Simulink stops with an overflow error; the HDL wraps instead.",
// ]
//
// [hdl_only]
//
// [mask_missing]
// cmplx_a = 'single real lane: complex lanes are not modelled'
// cmplx_b = 'single real lane: complex lanes are not modelled'
// misc = 'misc pass-through (misci/misco ports) is not implemented'
// floating_point = 'floating point is not implemented'
// float_type = 'floating point is not implemented'
// input_vec_a = 'single lane: the lane count is not modelled'
// input_vec_b = 'single lane: the lane count is not modelled'
// frac_width = 'floating point is not implemented'
// exp_width = 'floating point is not implemented'
// add_latency = "used only by complex (cmult) lanes; a real lane's latency is mult_latency (+fan_latency)"
// conv_latency = "used only by complex (cmult) lanes; a real lane's latency is mult_latency (+fan_latency)"
// max_fanout = 'fan-out replication factor only (no effect on values or latency)'
// fan_latency = 'input fan-out register stage not implemented: bus_replicate on a and b adds max(0,fan_latency) cycles (bus_mult_init.m:376-377,393-394); the HDL equals fan_latency=0'
// multiplier_implementation = 'implementation option, not modelled'
// pipeline_cmult_en = 'implementation option, not modelled'
// pipeline_latency = 'implementation option, not modelled'
//
// [ports]
// [ports.renamed]
// dout = 'a*b'
// [ports.missing]
// misci = 'misc=on only (not implemented)'
// misco = 'misc=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

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
    parameter int MULT_LATENCY = 1
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
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(MULT_LATENCY)
    ) u_convert (
        .clk (clk),
        .din (full),
        .dout(dout)
    );

endmodule
