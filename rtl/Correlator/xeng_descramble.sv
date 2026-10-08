// xeng_descramble — casper_library X-engine descrambler
// (casper_library_correlator.slx, Block SID 411; no _init.m, the mask
// initialization is in system_root.xml, the diagram in system_411.xml)
//
// Reorders the X-engine's tap-ordered output into one word per baseline
// (element), conjugating the wrapped-around baselines, and reads them out
// DEMUX_FACTOR narrow words per element:
//
//   acc ─ write_ctrl ─ data ─ x_cast ─┐
//                    ─ addr, we ──────┴─ Dual Port RAM port B (wide, 8P bits)
//   start (write_ctrl) ─ read_ctrl ─ addr ─ port A (narrow, OW bits) ─ acc_out
//   valid_out = Delay(read_ctrl.enable, RAM_LATENCY)
//   sync_out  = Logical AND (latency RAM_LATENCY) of start and sync_seen,
//               sync_seen = Register(d = en = sync, rst = start, init 0)
//
// Mask initialization (N = NUM_ANTS, L = ACC_LEN, D = DEMUX_FACTOR):
//   T = floor(N/2)+1 taps, NV = N*T valid words, E = N(N+1)/2 elements,
//   PIVOT = N/2*T + T*N/4, W = n_bits_xeng_out = 2*N_BITS + floor(log2 L)+1,
//   P = 2^ceil(log2 W), wide word 8P, OW = 8P/D,
//   DEL = ship_el_del = floor(L*N/NV/D) - 1 (< 0: the mask shows an errordlg
//         and uses 0; here a $warning and 0),
//   CNT = ship_el_cnt = (DEL == 0) ? D*E-1 : D*E,
//   K_START = ceil(3*NV/4), negedge_delay pulse_len = ceil(N/2)*L.
//
// W uses floor(log2 L)+1 while the X-engine taps' N_BITS_OUT uses
// 1+ceil(log2 L): they are equal for power-of-2 ACC_LEN, otherwise W is one
// bit narrower (as in the library; xeng handles the connection).
//
// RAM: depth (E+1)*D narrow words, i.e. E+1 wide words; port A only reads
// (narrow, latency RAM_LATENCY), port B only writes (wide). The narrow port
// maps narrow address r to bits [(r % D)*OW +: OW] of wide word r / D (Xilinx
// asymmetric-port convention: the lowest narrow address is the LSBs). With
// x_cast's block reversal this reads element e as narrow words e*D .. e*D+D-1,
// MSB block of the stored word first. Implemented as a wide dual_port_ram
// plus an output block select.
//
// Power-on: read_ctrl's done register starts at 0, so a read pass runs
// without any start; valid_out pulses for those D*E words (sync_out stays
// 0). The library RAM has initVector = [1:36*8], a leftover of the N = 8,
// D = 8 default; this RAM powers up to 0, so that power-on pass reads 0
// instead of the initVector values (the only deviation from the diagram).
//
// Parameters: NUM_ANTS, N_BITS, ACC_LEN, DEMUX_FACTOR are the mask
// parameters (stored defaults 8, 4, 128, 8). RAM_LATENCY (1 here, 2 in
// xeng_descramble_4ant) and PLATFORM (dual_port_ram vendor) are not mask
// parameters. NUM_ANTS must be even and >= 4 (PIVOT and the tap map assume
// it); DEMUX_FACTOR must be 1, 2, 4 or 8 (x_cast).
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
// block = 'casper_library_correlator.slx/xeng_descramble'
// deviations = [
//   'Power-on RAM contents: the HDL RAM powers up to 0. The library Dual Port RAM (system_411.xml) has initVector = [1:36*8], and xlDPBRAM.sgm loads mem = xl_state(init). So the spontaneous power-on read pass (read_ctrl done = 0) outputs narrow words 1, 2, 3, ... in Simulink but zeros in the HDL. How Sysgen fits the 288-entry vector to other depths ((E+1)*D) was not checked.',
//   "Read/write collision: with write_mode_B = 'No Read On Write', xlDPBRAM.sgm (BinvalidatesA) makes port A return NaN when port B writes the same wide word in the same cycle. The HDL dual_port_ram returns defined data instead. Legal xeng traffic never collides; the tests assert this.",
//   "NUM_ANTS odd or < 4 is a $fatal. Simulink builds these (the block description says 'NOT TESTED FOR non-2^N antennas'), but the pivot_pnt / Counter2 range is then non-integer or degenerate.",
// ]
//
// [hdl_only]
// RAM_LATENCY = 'RAM latency fixed in the diagram (1 here, 2 in xeng_descramble_4ant)'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// W = 'derived from other parameters (do not override)'
// P = 'derived from other parameters (do not override)'
// OW = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module xeng_descramble #(
    parameter int    NUM_ANTS     = 8,
    parameter int    N_BITS       = 4,
    parameter int    ACC_LEN      = 128,
    parameter int    DEMUX_FACTOR = 8,
    parameter int    RAM_LATENCY  = 1,
    parameter string PLATFORM     = "GENERIC",
    // derived (mask initialization); not to be overridden
    parameter int    W            = 2 * N_BITS + $clog2(ACC_LEN + 1),
    parameter int    P            = 1 << $clog2(W),
    parameter int    OW           = 8 * P / DEMUX_FACTOR
)(
    input  logic          clk,
    input  logic [8*W-1:0] acc,
    input  logic          valid,
    input  logic          sync,
    input  logic          win_valid,
    output logic [OW-1:0] acc_out,
    output logic          valid_out,
    output logic          sync_out
);

    localparam int N        = NUM_ANTS;
    localparam int D        = DEMUX_FACTOR;
    localparam int T        = N / 2 + 1;
    localparam int NV       = N * T;
    localparam int E        = N * (N + 1) / 2;
    localparam int DEL_RAW  = (ACC_LEN * N) / (NV * D) - 1;
    localparam int DEL      = (DEL_RAW < 0) ? 0 : DEL_RAW;
    localparam int CNT      = (DEL == 0) ? D * E - 1 : D * E;
    localparam int DEL_BITS = ($clog2(DEL + 1) < 1) ? 1 : $clog2(DEL + 1);
    localparam int RD_BITS  = $clog2(CNT + 1);
    localparam int WA_BITS  = $clog2(E);
    localparam int RAM_AW   = $clog2(E + 1);
    localparam int SUB_BITS = (D > 1) ? $clog2(D) : 1;

    initial begin
        if (N < 4 || N % 2 != 0)
            $fatal(1, "xeng_descramble: NUM_ANTS must be even and >= 4 (got %0d)", N);
        if (D != 1 && D != 2 && D != 4 && D != 8)
            $fatal(1, "xeng_descramble: DEMUX_FACTOR must be 1, 2, 4 or 8 (got %0d)", D);
        if (RAM_LATENCY < 1)
            $fatal(1, "xeng_descramble: RAM_LATENCY must be >= 1");
        if (W != 2 * N_BITS + $clog2(ACC_LEN + 1) || P != (1 << $clog2(W)) || OW != 8 * P / D)
            $fatal(1, "xeng_descramble: W / P / OW are derived, do not override");
        if (DEL_RAW < 0)
            $warning("xeng_descramble: insufficient output space for this configuration (ship_el_del < 0), using 0 as the mask does");
    end

    // ── write side ───────────────────────────────────────────────────────────
    logic               start;
    logic [WA_BITS-1:0] waddr;
    logic [8*W-1:0]     wdata;
    logic               we;
    logic [8*P-1:0]     wide_in;

    write_ctrl #(.NUM_ANTS(N), .ACC_LEN(ACC_LEN), .W(W)) u_write_ctrl (
        .clk(clk), .sync(sync), .data_in(acc), .xeng_valid(valid), .window_valid(win_valid),
        .start_readout(start), .write_addr(waddr), .data_out(wdata), .enable(we));

    x_cast #(.N_BITS_IN(W), .N_BITS_OUT(P), .FIX_PNT_POS((N_BITS - 1) * 2),
             .DEMUX_FACTOR(D)) u_x_cast (.din(wdata), .dout(wide_in));

    // ── read side ────────────────────────────────────────────────────────────
    logic [RD_BITS-1:0] raddr;
    logic               ren;

    read_ctrl #(.DEL(DEL), .CNT(CNT), .DEL_BITS(DEL_BITS), .RD_BITS(RD_BITS)) u_read_ctrl (
        .clk(clk), .start(start), .read_addr(raddr), .enable(ren));

    // ── dual-port RAM: port A narrow read, port B wide write ─────────────────
    logic [RAM_AW-1:0]   ra_wide;
    logic [SUB_BITS-1:0] ra_sub, ra_sub_d;
    logic [8*P-1:0]      rdata, rdata_d;

    assign ra_wide = RAM_AW'(raddr / D);
    assign ra_sub  = SUB_BITS'(raddr % D);

    dual_port_ram #(.DATA_WIDTH(8 * P), .ADDR_WIDTH(RAM_AW), .PLATFORM(PLATFORM)) u_ram (
        .clk(clk),
        .we_a(1'b0), .addr_a(ra_wide), .din_a('0), .dout_a(rdata),
        .we_b(we), .addr_b(RAM_AW'(waddr)), .din_b(wide_in), .dout_b());

    // extra output registers of a RAM_LATENCY > 1 RAM, and the narrow select
    pipeline #(.BITWIDTH(8 * P), .CSP_LATENCY(RAM_LATENCY - 1)) u_rdata_dly (
        .clk(clk), .din(rdata), .dout(rdata_d));
    pipeline #(.BITWIDTH(SUB_BITS), .CSP_LATENCY(RAM_LATENCY)) u_sub_dly (
        .clk(clk), .din(ra_sub), .dout(ra_sub_d));

    assign acc_out = rdata_d[ra_sub_d * OW +: OW];

    // ── valid / sync out ─────────────────────────────────────────────────────
    logic sync_seen, sync_out_raw;

    delay #(.LATENCY(RAM_LATENCY), .BITWIDTH(1)) u_valid_out (
        .clk(clk), .din(ren), .dout(valid_out));

    register #(.BITWIDTH(1), .USE_RST(1), .USE_ENABLE(1), .INIT_VAL(0)) u_sync_seen (
        .clk(clk), .rst(start), .en(sync), .d(sync), .q(sync_seen));

    logic [0:0] and_in [2];
    logic [0:0] and_out;
    assign and_in[0] = start;
    assign and_in[1] = sync_seen;
    logical #(.NBITS(1), .NINPUTS(2), .LATENCY(RAM_LATENCY), .FUNC(0)) u_sync_out (
        .clk(clk), .din(and_in), .dout(and_out));
    assign sync_out = and_out[0];

endmodule
