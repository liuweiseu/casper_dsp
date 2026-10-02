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
        .TYPE_OUT(1), .QUANTIZATION(0), .OVERFLOW(0), .LATENCY(MULT_LATENCY)
    ) u_mult (.clk(clk), .a(din), .b(coeff[COEFF_WIDTH-1:0]), .dout(taps_out));

endmodule
