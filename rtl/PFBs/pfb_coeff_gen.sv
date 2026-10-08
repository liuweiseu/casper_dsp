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
// block = 'casper_library_pfbs.slx/pfb_coeff_gen'
// deviations = [
//   "DEBUG_MODE != 0 is a $fatal (pfb_coeff_gen.sv:93); Simulink debug_mode='on' stores coefficient indices as Unsigned ROM words (pfb_coeff_gen_init.m atype/binpt/debug_option).",
//   'Coefficients are not computed by the HDL: the ROMs are read with $readmemh from COEFF_DIR/pfb_coeff_n<NPUT>_t<a>.mem written by rtl/PFBs/scripts/gen_pfb_coeffs.py, so WINDOW_TYPE and FWIDTH are declared only; changing them without regenerating the files has no effect, and a missing file leaves the ROM all zero with only a simulator warning (rtl/Delays/rom.sv initial block), whereas Simulink evaluates pfb_coeff_gen_calc() at init time.',
//   "The generator reimplements MATLAB window() in Python and raises an error for 'chebwin' and 'userwindow' (gen_pfb_coeffs.py:157-163); it accepts the mask's 'bohamwin' spelling as bohmanwin, while MATLAB window('bohamwin',N) has no such function and is expected to fail in Simulink (unverified). Fixed defaults assumed: gausswin alpha 2.5, kaiser beta 0.5, tukeywin r 0.5.",
//   'ROM quantization matches the Xilinx ROM model (xlSPROM.sgm:16 xfix with xlRound, xlSaturate = round half away from zero, saturate) and gen_pfb_coeffs.py quantize_coeff (floor(|x|+0.5), saturate); bit-exactness on exact .5 ties additionally depends on Python and MATLAB producing identical double-precision window*sinc values, which is unverified.',
//   "BRAM_LATENCY < 1 is a $fatal (pfb_coeff_gen.sv:95): Simulink's Xilinx ROM accepts latency 0 (combinational read, xlSPROM.sgm latency==0 branch); for BRAM_LATENCY >= 1 the HDL uses a 1-cycle ROM plus a BRAM_LATENCY-1 register pipeline, all powering up to 0 like the ROM's output delay line (xlSPROM.sgm, zeros(1,latency)).",
//   'PFB_SIZE-N_INPUTS < 1 and NPUT outside 0..2^N_INPUTS-1 are $fatal (pfb_coeff_gen.sv:94,96-97); Simulink would build a 0-bit Counter / index past the window and fail or misbehave at compile time.',
//   'COEFF_DIST_MEM is ignored (memory type follows PLATFORM); in Simulink it only selects distributed vs block RAM for the ROMs, which does not change values.',
// ]
//
// [params.COEFF_DIST_MEM]
// mask = 'CoeffDistMem'
// type = 'checkbox'
// note = 'declared only: Simulink sets ROM distributed_mem (Distributed memory / Block RAM); the HDL memory follows PLATFORM'
// [params.COEFF_DIST_MEM.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.DEBUG_MODE]
// mask = 'debug_mode'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = 'on fills the ROMs with coefficient indices (Unsigned, bin_pt 0) in Simulink'
// [params.DEBUG_MODE.values]
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
// [params.WINDOW_TYPE]
// mask = 'WindowType'
// type = 'edit'
// note = 'free-text mask field (Evaluate off): enter the HDL string value itself, e.g. hamming (unlike pfb_fir_real, where WindowType is a popup)'
//
// [hdl_only]
// DIN_WIDTH = 'inherited width: Simulink takes it from the input signal'
// COEFF_DIR = 'implementation: memory initialization file'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
//
// [ports]
// order = 'Simulink inputs are din(1), sync(2) and outputs dout(1), sync_out(2), coeff(3) (pfb_coeff_gen_init.m reuse_block Port); the HDL declares sync before din and sync_out before dout'
// note = 'Simulink coeff is one concatenated UFix_(TotalTaps*CoeffBitWidth)_0 bus (Concat, ROM1 in the MSBs, each ROM reinterpreted Unsigned bin_pt 0); the HDL coeff is an array over TOTAL_TAPS with coeff[a-1] = ROM a (raw bits of Fix_COEFF_BIT_WIDTH_(COEFF_BIT_WIDTH-1))'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

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
    pipeline #(.BITWIDTH(DIN_WIDTH), .CSP_LATENCY(DLY)) u_delay1 (.clk(clk), .din(din), .dout(dout));
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(DLY)) u_delay (.clk(clk), .din(sync), .dout(sync_out));

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

        pipeline #(.BITWIDTH(AW), .CSP_LATENCY(FAN_LATENCY)) u_fan_delay (
            .clk(clk), .din(cnt), .dout(addr));

        // ROM latency BRAM_LATENCY: rom (1) + pipeline (BRAM_LATENCY-1)
        rom #(
            .DATA_WIDTH(COEFF_BIT_WIDTH), .ADDR_WIDTH(AW),
            .INIT_FILE({COEFF_DIR, "pfb_coeff_n", itoa(NPUT), "_t", itoa(a), ".mem"}),
            .PLATFORM(PLATFORM)
        ) u_rom (.clk(clk), .addr(addr), .dout(rom_q));
        pipeline #(.BITWIDTH(COEFF_BIT_WIDTH), .CSP_LATENCY(BRAM_LATENCY - 1)) u_rom_dly (
            .clk(clk), .din(rom_q), .dout(rom_d));

        // Concat + Register (latency 1)
        pipeline #(.BITWIDTH(COEFF_BIT_WIDTH), .CSP_LATENCY(1)) u_register (
            .clk(clk), .din(rom_d), .dout(coeff[a-1]));
    end

endmodule
