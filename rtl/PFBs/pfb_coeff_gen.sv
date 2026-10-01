// pfb_coeff_gen — FIR coefficients of one PFB input, one ROM per tap
//
// Corresponds to casper_library's pfb_coeff_gen (pfb_coeff_gen_init.m,
// debug_mode off). As the init script builds it:
//
//   sync ─► Counter (free running, up, PFB_SIZE-N_INPUTS bits, rst = sync)
//            ─► fan_delay<a> (FAN_LATENCY) ─► ROM<a> (BRAM_LATENCY) ─┐  a = 1 … TOTAL_TAPS
//                                       Concat (ROM1 = MSB) ─► Register ─► coeff
//   din  ─► Delay1 (BRAM_LATENCY+1+FAN_LATENCY) ─► dout
//   sync ─► Delay  (BRAM_LATENCY+1+FAN_LATENCY) ─► sync_out
//
// so coeff carries, for the sample on dout, the coefficients of counter
// value k = cycles since the last sync - 1 (k = 0 for the sample right after
// sync). coeff[a-1] is ROM a (casper's Concat input a; coeff[0] is the MSB
// slice of casper's coeff bus), a COEFF_BIT_WIDTH-bit signed word with
// binary point COEFF_BIT_WIDTH-1.
//
// ROM a holds pfb_coeff_gen_calc(PFB_SIZE, TOTAL_TAPS, WINDOW_TYPE,
// N_INPUTS, NPUT, FWIDTH, a): entries (a-1)·2^PFB_SIZE + NPUT + i·2^N_INPUTS,
// i = 0 … 2^(PFB_SIZE-N_INPUTS)-1, of window(WINDOW_TYPE, TOTAL_TAPS·2^PFB_SIZE)
// · sinc(FWIDTH·(t/2^PFB_SIZE - TOTAL_TAPS/2)), t = 0.5, 1.5, …. The module
// reads it from COEFF_DIR + "pfb_coeff_n<NPUT>_t<a>.mem"; write the files
// with rtl/PFBs/scripts/gen_pfb_coeffs.py. WINDOW_TYPE and FWIDTH are
// declared for traceability (they only shape the tables).
//
// Declared for traceability only: COEFF_DIST_MEM (distributed vs block RAM;
// see PLATFORM) is ignored; DEBUG_MODE (ROMs holding coefficient indices)
// must be 0.

module pfb_coeff_gen #(
    parameter int    PFB_SIZE        = 5,
    parameter int    COEFF_BIT_WIDTH = 18,
    parameter int    TOTAL_TAPS      = 4,
    parameter int    COEFF_DIST_MEM  = 0,
    parameter string WINDOW_TYPE     = "hamming",
    parameter int    BRAM_LATENCY    = 2,
    parameter int    N_INPUTS        = 1,
    parameter int    NPUT            = 0,
    parameter real   FWIDTH          = 1.0,
    parameter int    FAN_LATENCY     = 1,
    parameter int    DIN_WIDTH       = 8,
    parameter string COEFF_DIR       = "",
    parameter string PLATFORM        = "GENERIC",
    // declared, not implemented (see header)
    parameter int    DEBUG_MODE      = 0
)(
    input  logic                       clk,
    input  logic                       sync,
    input  logic [DIN_WIDTH-1:0]       din,
    output logic                       sync_out,
    output logic [DIN_WIDTH-1:0]       dout,
    output logic [COEFF_BIT_WIDTH-1:0] coeff [TOTAL_TAPS]
);

    localparam int AW  = PFB_SIZE - N_INPUTS;            // counter / ROM address bits
    localparam int DLY = BRAM_LATENCY + 1 + FAN_LATENCY;

    function automatic string itoa(int v);
        string str = "";
        if (v == 0) return "0";
        while (v > 0) begin
            str = {string'(8'(48 + v % 10)), str};
            v   = v / 10;
        end
        return str;
    endfunction

    if (DEBUG_MODE != 0)  $fatal(1, "pfb_coeff_gen: DEBUG_MODE is not implemented");
    if (AW < 1)           $fatal(1, "pfb_coeff_gen: PFB_SIZE - N_INPUTS must be >= 1");
    if (BRAM_LATENCY < 1) $fatal(1, "pfb_coeff_gen: BRAM_LATENCY must be >= 1");
    if (NPUT < 0 || NPUT >= (1 << N_INPUTS))
        $fatal(1, "pfb_coeff_gen: NPUT must be in 0 .. 2^N_INPUTS-1");

    // ── data and sync delays ────────────────────────────────────────────────
    pipeline #(.BITWIDTH(DIN_WIDTH), .LATENCY(DLY)) u_delay1 (.clk(clk), .din(din), .dout(dout));
    pipeline #(.BITWIDTH(1), .LATENCY(DLY)) u_delay (.clk(clk), .din(sync), .dout(sync_out));

    // ── address counter (casper Counter: free running, rst = sync) ─────────
    logic [AW-1:0] cnt;

    counter #(
        .COUNTER_TYPE(0), .NBITS(AW), .COUNT_DIR(0), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0)
    ) u_counter (.clk(clk), .rst(sync), .enable(1'b1), .dout(cnt));

    // ── one ROM per tap ─────────────────────────────────────────────────────
    for (genvar a = 1; a <= TOTAL_TAPS; a++) begin : GEN_TAP
        logic [AW-1:0]              addr;
        logic [COEFF_BIT_WIDTH-1:0] rom_q, rom_d;

        pipeline #(.BITWIDTH(AW), .LATENCY(FAN_LATENCY)) u_fan_delay (
            .clk(clk), .din(cnt), .dout(addr));

        // ROM latency BRAM_LATENCY: rom (1) + pipeline (BRAM_LATENCY-1)
        rom #(
            .DATA_WIDTH(COEFF_BIT_WIDTH), .ADDR_WIDTH(AW),
            .INIT_FILE({COEFF_DIR, "pfb_coeff_n", itoa(NPUT), "_t", itoa(a), ".mem"}),
            .PLATFORM(PLATFORM)
        ) u_rom (.clk(clk), .addr(addr), .dout(rom_q));
        pipeline #(.BITWIDTH(COEFF_BIT_WIDTH), .LATENCY(BRAM_LATENCY - 1)) u_rom_dly (
            .clk(clk), .din(rom_q), .dout(rom_d));

        // Concat + Register (latency 1)
        pipeline #(.BITWIDTH(COEFF_BIT_WIDTH), .LATENCY(1)) u_register (
            .clk(clk), .din(rom_d), .dout(coeff[a-1]));
    end

endmodule
