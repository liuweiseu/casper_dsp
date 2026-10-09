// scale — multiply by a power of two, then requantize
//
// dout = convert(din * 2^SCALE_FACTOR)
//
// Scaling by 2^SCALE_FACTOR is a pure reinterpretation of the input word: the
// bits are unchanged and the binary point moves from BIN_PT_IN to
// BIN_PT_IN - SCALE_FACTOR (as in the Xilinx Scale block). The rescaled
// value is then requantized to the output format by a convert instance, which
// also provides the LATENCY pipeline. Corresponds to a single lane of
// casper_library's bus_scale. SCALE_FACTOR may be negative (divide) or
// positive (multiply).
//
// Encodings (common to all fixed-point modules in rtl/Bus/ and
// rtl/Multipliers/):
//   TYPE_*       : 0 = unsigned, 1 = signed
//   QUANTIZATION : 0 = truncate, 1 = round half away from zero,
//                  2 = round half to even
//   OVERFLOW     : 0 = wrap, 1 = saturate (2 = flag as error -> wrap)
//   LATENCY      : 0 = combinational, N > 0 = N register stages
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
// block = 'casper_library_bus.slx/bus_scale'
// deviations = [
//   'bus_scale is a pure reinterpretation with zero latency. xlScale.sgm only moves the binary point (bin_pt_in - scale_factor), and bus_create concatenates the unchanged bits (bus_scale_init.m:126,140). The HDL adds a requantizing convert plus LATENCY registers, so it is bit- and cycle-exact only with N_BITS_OUT=N_BITS_IN, BIN_PT_OUT=BIN_PT_IN-SCALE_FACTOR, TYPE_OUT=TYPE_IN and LATENCY=0. The HDL default LATENCY=1 adds one cycle.',
//   'misc: bus_scale passes misci straight to misco with no delay (bus_scale_init.m:160-165); not implemented in the HDL.',
// ]
//
// [mask_set.misc]
// value = 'off'
//
// [hdl_only]
// N_BITS_OUT = 'the HDL adds a requantizing convert after the scale'
// BIN_PT_OUT = 'the HDL adds a requantizing convert after the scale'
// TYPE_OUT = 'the HDL adds a requantizing convert after the scale'
// QUANTIZATION = 'the HDL adds a requantizing convert after the scale'
// OVERFLOW = 'the HDL adds a requantizing convert after the scale'
// LATENCY = 'latency of the HDL requantizer (bus_scale has none)'
//
// [mask_missing]
// cmplx = 'single real lane: complex lanes are not modelled'
//
// [ports]
// [ports.renamed]
// [ports.missing]
// misci = 'misc=on only (not implemented)'
// misco = 'misc=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module scale #(
    parameter int N_BITS_IN    = 16,
    parameter int BIN_PT_IN    = 8,
    parameter int TYPE_IN      = 1,
    parameter int SCALE_FACTOR = -1,
    parameter int N_BITS_OUT   = 16,
    parameter int BIN_PT_OUT   = 8,
    parameter int TYPE_OUT     = 1,
    parameter int QUANTIZATION = 0,
    parameter int OVERFLOW     = 0,
    parameter int LATENCY      = 1
)(
    input  logic                  clk,
    input  logic [N_BITS_IN-1:0]  din,
    output logic [N_BITS_OUT-1:0] dout
);

    convert #(
        .N_BITS_IN (N_BITS_IN),  .BIN_PT_IN (BIN_PT_IN - SCALE_FACTOR), .TYPE_IN (TYPE_IN),
        .N_BITS_OUT(N_BITS_OUT), .BIN_PT_OUT(BIN_PT_OUT),               .TYPE_OUT(TYPE_OUT),
        .QUANTIZATION(QUANTIZATION), .OVERFLOW(OVERFLOW), .CSP_LATENCY(LATENCY)
    ) u_convert (
        .clk (clk),
        .din (din),
        .dout(dout)
    );

endmodule
