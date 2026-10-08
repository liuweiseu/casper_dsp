// tap_real — middle tap of a real PFB FIR (one of TotalTaps-2)
//
// Corresponds to casper_library's tap_real (its internal diagram in
// casper_library_pfbs.slx):
//
//   din ─┬─► delay_bram (DELAY) ─────────────────────────────► dout
//        └─► Reinterpret Fix_DATA_WIDTH_(DATA_WIDTH-1) ─┐
//   coeff ─┬─► Slice [COEFF_WIDTH-1:0] ─► Reinterpret   ├─► Mult (Full, MULT_LATENCY) ─► taps_out
//          │        Fix_COEFF_WIDTH_COEFF_FRAC_WIDTH ───┘
//          └─► Slice [MSB : COEFF_WIDTH] ───────────────────────► coeff_out (no delay)
//   sync ─► sync_delay (DELAY) ─────────────────────────────────► sync_out
//
// The tap multiplies its own (undelayed) input sample by the lowest
// COEFF_WIDTH bits of the coefficient bus and forwards the rest of the bus
// unchanged; only data and sync advance by DELAY = 2^(PFBSize-n_inputs) ·
// n_pol_blocks per hop (pfb_fir_real_init.m), so tap t multiplies the sample
// (t-1)·DELAY cycles older than the first tap with the same coefficient
// bus. With pfb_coeff_gen's Concat (ROM 1 = MSB), tap t uses ROM
// TotalTaps+1-t, which makes the chain a windowed-presum PFB:
// y_k(f) = Σ_j h[j] x[(f-T+1)·N + j], j ≡ k (mod N).
//
// taps_out is the full-precision product: DATA_WIDTH+COEFF_WIDTH bits,
// binary point DATA_WIDTH-1+COEFF_FRAC_WIDTH, signed.
//
// N_COEFFS is the number of COEFF_WIDTH-bit coefficients on the incoming
// bus (casper infers the width; the remainder is N_COEFFS-1 coefficients).
// Declared for traceability only: USE_HDL and USE_EMBEDDED (multiplier
// implementation) are ignored.
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
// block = 'casper_library_pfbs.slx/tap_real'
// deviations = [
//   "BRAM_LATENCY is declared but not passed to delay_bram (tap_real.sv:78), so it has no effect: dout is din delayed exactly DELAY cycles; Simulink's delay_bram (system_39.xml DelayLen=delay, bram_latency=bram_latency) gives the same total delay but errors when delay <= bram_latency+1 (delay_bram_init.m:40-43), which the HDL accepts.",
//   'The coefficient bus width is fixed by N_COEFFS*COEFF_WIDTH in the HDL, whereas Simulink inherits it from the driving signal; N_COEFFS < 2 is a $fatal (tap_real.sv:76) because coeff_out would be empty.',
//   "USE_HDL and USE_EMBEDDED are declared only; in Simulink the mask init only sets the Mult's use_behavioral_HDL/use_embedded, so values are unaffected.",
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
// [hdl_only]
// N_COEFFS = "coefficient count; casper infers the coeff bus width from the input signal (Slice1 'Two Bit Locations' MSB..coeff_width, system_39.xml)"
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
//
// [ports]
// note = "library MaskType is 'pfb_tap_real' but the library block is named tap_real"
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module tap_real #(
    parameter int    MULT_LATENCY     = 2,
    parameter int    COEFF_WIDTH      = 12,
    parameter int    COEFF_FRAC_WIDTH = 11,
    parameter int    DELAY            = 4,
    parameter int    DATA_WIDTH       = 8,
    parameter int    BRAM_LATENCY     = 1,
    parameter int    N_COEFFS         = 3,
    parameter string PLATFORM         = "GENERIC",
    // declared, not implemented (see header)
    parameter int    USE_HDL          = 1,
    parameter int    USE_EMBEDDED     = 0
)(
    input  logic                                 clk,
    input  logic [DATA_WIDTH-1:0]                din,
    input  logic                                 sync,
    input  logic [N_COEFFS*COEFF_WIDTH-1:0]      coeff,
    output logic [DATA_WIDTH-1:0]                dout,
    output logic                                 sync_out,
    output logic [(N_COEFFS-1)*COEFF_WIDTH-1:0]  coeff_out,
    output logic [DATA_WIDTH+COEFF_WIDTH-1:0]    taps_out
);

    if (N_COEFFS < 2) $fatal(1, "tap_real: N_COEFFS must be >= 2 (use last_tap_real for the last tap)");

    delay_bram #(.BITWIDTH(DATA_WIDTH), .DELAY_LEN(DELAY), .PLATFORM(PLATFORM)) u_delay_bram (
        .clk(clk), .din(din), .dout(dout));

    sync_delay #(.DELAY_LEN(DELAY)) u_sync_delay (.clk(clk), .din(sync), .dout(sync_out));

    assign coeff_out = coeff[N_COEFFS*COEFF_WIDTH-1:COEFF_WIDTH];

    multiplier #(
        .N_BITS_A(DATA_WIDTH), .BIN_PT_A(DATA_WIDTH - 1), .TYPE_A(1),
        .N_BITS_B(COEFF_WIDTH), .BIN_PT_B(COEFF_FRAC_WIDTH), .TYPE_B(1),
        .N_BITS_OUT(DATA_WIDTH + COEFF_WIDTH), .BIN_PT_OUT(DATA_WIDTH - 1 + COEFF_FRAC_WIDTH),
        .TYPE_OUT(1), .QUANTIZATION(0), .OVERFLOW(0), .MULT_LATENCY(MULT_LATENCY)
    ) u_mult (.clk(clk), .a(din), .b(coeff[COEFF_WIDTH-1:0]), .dout(taps_out));

endmodule
