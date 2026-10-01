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
