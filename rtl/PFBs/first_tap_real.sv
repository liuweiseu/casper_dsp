// first_tap_real — first tap of a real PFB FIR
//
// Corresponds to casper_library's first_tap_real (its internal diagram in
// casper_library_pfbs.slx; first_tap_real_init.m only sets the multiplier
// implementation). Same as tap_real, with the parameters pfb_fir_real
// propagates to it:
//
//   DELAY        = 2^(PFB_SIZE-N_INPUTS) · N_POL_BLOCKS     (delay_bram, sync_delay)
//   own coeff    = coeff[COEFF_BIT_WIDTH-1:0], Fix_COEFF_BIT_WIDTH_(COEFF_BIT_WIDTH-1)
//   coeff_out    = coeff[TOTAL_TAPS·COEFF_BIT_WIDTH-1 : COEFF_BIT_WIDTH]  (no delay)
//   data         = Fix_BIT_WIDTH_IN_(BIT_WIDTH_IN-1)
//   taps_out     = din × own coeff, full precision, latency MULT_LATENCY:
//                  BIT_WIDTH_IN+COEFF_BIT_WIDTH bits, binary point
//                  BIT_WIDTH_IN+COEFF_BIT_WIDTH-2
//
// coeff is pfb_coeff_gen's concatenated bus (ROM 1 = MSB), so the first tap
// uses ROM TOTAL_TAPS (the last segment of the window): its sample is the
// newest one of the windowed presum (see tap_real).
//
// Declared for traceability only: USE_HDL and USE_EMBEDDED are ignored.
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
// block = 'casper_library_pfbs.slx/first_tap_real'
// deviations = [
//   "BRAM_LATENCY is passed to tap_real but never reaches delay_bram (rtl/PFBs/tap_real.sv instantiates delay_bram without it), so the data delay is always exactly 2^(PFB_SIZE-N_INPUTS)*N_POL_BLOCKS cycles; Simulink's delay_bram also totals DelayLen cycles but errors when DelayLen <= bram_latency+1 (delay_bram_init.m:40-43), a configuration the HDL silently accepts.",
//   'USE_HDL and USE_EMBEDDED are declared only (first_tap_real.sv header); in Simulink they only switch the Mult implementation (first_tap_real_init.m set_param Mult use_behavioral_HDL/use_embedded), so values are unaffected.',
//   'TOTAL_TAPS < 2 is a $fatal in the HDL (first_tap_real.sv:71); in Simulink Slice1 would get width CoeffBitWidth*(TotalTaps-1) = 0 and fail to compile, so no valid Simulink configuration is lost.',
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
// [params.PFB_SIZE]
// mask = 'PFBSize'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [params.COEFF_BIT_WIDTH]
// mask = 'CoeffBitWidth'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [params.TOTAL_TAPS]
// mask = 'TotalTaps'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [params.BIT_WIDTH_IN]
// mask = 'BitWidthIn'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [hdl_only]
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// WindowType = 'unused by the Simulink block as well: neither first_tap_real_init.m nor the diagram (system_82.xml) reads it'
// fwidth = 'unused by the Simulink block as well: neither first_tap_real_init.m nor the diagram (system_82.xml) reads it'
//
// [ports]
// [ports.renamed]
// coeff = 'coeffs'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module first_tap_real #(
    parameter int    PFB_SIZE        = 6,
    parameter int    N_INPUTS        = 1,
    parameter int    N_POL_BLOCKS    = 1,
    parameter int    COEFF_BIT_WIDTH = 8,
    parameter int    TOTAL_TAPS      = 4,
    parameter int    BIT_WIDTH_IN    = 8,
    parameter int    MULT_LATENCY    = 2,
    parameter int    BRAM_LATENCY    = 2,
    parameter string PLATFORM        = "GENERIC",
    // declared, not implemented (see header)
    parameter int    USE_HDL         = 1,
    parameter int    USE_EMBEDDED    = 0
)(
    input  logic                                         clk,
    input  logic [BIT_WIDTH_IN-1:0]                      din,
    input  logic                                         sync,
    input  logic [TOTAL_TAPS*COEFF_BIT_WIDTH-1:0]        coeff,
    output logic [BIT_WIDTH_IN-1:0]                      dout,
    output logic                                         sync_out,
    output logic [(TOTAL_TAPS-1)*COEFF_BIT_WIDTH-1:0]    coeff_out,
    output logic [BIT_WIDTH_IN+COEFF_BIT_WIDTH-1:0]      taps_out
);

    if (TOTAL_TAPS < 2) $fatal(1, "first_tap_real: TOTAL_TAPS must be >= 2");

    tap_real #(
        .MULT_LATENCY(MULT_LATENCY), .COEFF_WIDTH(COEFF_BIT_WIDTH),
        .COEFF_FRAC_WIDTH(COEFF_BIT_WIDTH - 1),
        .DELAY((1 << (PFB_SIZE - N_INPUTS)) * N_POL_BLOCKS),
        .DATA_WIDTH(BIT_WIDTH_IN), .BRAM_LATENCY(BRAM_LATENCY), .N_COEFFS(TOTAL_TAPS),
        .PLATFORM(PLATFORM)
    ) u_tap (
        .clk(clk), .din(din), .sync(sync), .coeff(coeff),
        .dout(dout), .sync_out(sync_out), .coeff_out(coeff_out), .taps_out(taps_out));

endmodule
