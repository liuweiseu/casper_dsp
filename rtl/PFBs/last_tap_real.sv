// last_tap_real — last tap of a real PFB FIR
//
// Corresponds to casper_library's last_tap_real (its internal diagram in
// casper_library_pfbs.slx; last_tap_real_init.m only sets the multiplier
// implementation):
//
//   din   ─► Reinterpret Fix_BIT_WIDTH_IN_(BIT_WIDTH_IN-1) ─┐
//   coeff ─► Reinterpret Fix_COEFF_BIT_WIDTH_(COEFF_BIT_WIDTH-1) ─┴► Mult (Full, MULT_LATENCY) ─► tap_out
//   sync  ─► Delay (MULT_LATENCY) ──────────────────────────────────► sync_out
//
// No data or coefficients are forwarded. coeff is the last COEFF_BIT_WIDTH
// bits left on the bus (ROM 1 of pfb_coeff_gen). In pfb_fir_real, tap_out
// is the adder_tree's last data input and sync_out its sync, aligned with
// all taps' products (each tap's multiplier has the same MULT_LATENCY).
//
// tap_out: BIT_WIDTH_IN+COEFF_BIT_WIDTH bits, binary point
// BIT_WIDTH_IN+COEFF_BIT_WIDTH-2, signed. Declared for traceability only:
// USE_HDL and USE_EMBEDDED are ignored.
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
// block = 'casper_library_pfbs.slx/last_tap_real'
// deviations = [
//   "USE_HDL and USE_EMBEDDED are declared only (last_tap_real.sv header); in Simulink last_tap_real_init.m only copies them to the Mult's use_behavioral_HDL/use_embedded, which does not change the Full-precision product (system_5.xml Mult precision Full, latency mult_latency).",
// ]
//
// [params.USE_HDL]
// mask = 'use_hdl'
// type = 'checkbox'
// note = "declared only: selects the Xilinx Mult's behavioural-HDL implementation; no numeric effect (Full precision)"
// [params.USE_HDL.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_EMBEDDED]
// mask = 'use_embedded'
// type = 'checkbox'
// note = 'declared only: selects DSP48 vs fabric for the Xilinx Mult; the mask forces it off when use_hdl is on'
// [params.USE_EMBEDDED.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.BIT_WIDTH_IN]
// mask = 'BitWidthIn'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [params.COEFF_BIT_WIDTH]
// mask = 'CoeffBitWidth'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module last_tap_real #(
    parameter int BIT_WIDTH_IN    = 8,
    parameter int COEFF_BIT_WIDTH = 8,
    parameter int MULT_LATENCY    = 2,
    // declared, not implemented (see header)
    parameter int USE_HDL         = 1,
    parameter int USE_EMBEDDED    = 0
)(
    input  logic                                    clk,
    input  logic [BIT_WIDTH_IN-1:0]                 din,
    input  logic                                    sync,
    input  logic [COEFF_BIT_WIDTH-1:0]              coeff,
    output logic [BIT_WIDTH_IN+COEFF_BIT_WIDTH-1:0] tap_out,
    output logic                                    sync_out
);

    multiplier #(
        .N_BITS_A(BIT_WIDTH_IN), .BIN_PT_A(BIT_WIDTH_IN - 1), .TYPE_A(1),
        .N_BITS_B(COEFF_BIT_WIDTH), .BIN_PT_B(COEFF_BIT_WIDTH - 1), .TYPE_B(1),
        .N_BITS_OUT(BIT_WIDTH_IN + COEFF_BIT_WIDTH),
        .BIN_PT_OUT(BIT_WIDTH_IN + COEFF_BIT_WIDTH - 2),
        .TYPE_OUT(1), .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
    ) u_mult (.clk(clk), .a(din), .b(coeff), .dout(tap_out));

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(MULT_LATENCY)) u_delay (
        .clk(clk), .din(sync), .dout(sync_out));

endmodule
