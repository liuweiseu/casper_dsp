// snapshot — casper_library_scopes/snapshot: capture 2^NSAMPLES words of din
// into a shared BRAM under software control (BRAM storage)
//
// The block holds three yellow blocks, which the HDL does not implement.
// It cuts at their boundaries instead:
//   ctrl   swreg  <block>/ctrl   From Processor, 32 bits -> input  ctrl
//   status swreg  <block>/status To Processor,   32 bits -> output status
//   bram   shared_bram <block>/bram (addr_width NSAMPLES, data_width
//          DATA_WIDTH)   -> outputs bram_addr, bram_data_in, bram_we;
//                           input  bram_data_out (unused, as in Simulink)
// The software names are <design>_<block path>_ctrl / _status / _bram; the
// wrapper that connects the ports keeps them. The swreg / shared_bram
// internals stay with the yellow blocks: the status swreg's own register
// (cast_gw, latency 1), and the shared_bram's address manipulation
// (calc_add) and 32-bit word order (munge_in / munge_out).
//
// ctrl bits: 0 enable (a rising edge arms the capture), 1 trig_src (1 =
// trigger at once, 0 = wait for trig), 2 valid_src (1 = write every cycle,
// 0 = write when we), 3 circular capture (no effect without CIRCAP).
//
// Structure as built by snapshot_init.m (offset, circap, value, ext_arm,
// ext_circ off), with ctrl bits 0..2 delayed one cycle:
//   init      = rising edge of enable
//   trig_sel  = trig_src ? 1 : trig;     we_sel = valid_src ? 1 : we
//   armed     : set by init, cleared by trig_sel & ~init      (Register1)
//   go        : init -> 0, else while armed follows trig_sel   (Register6)
//   write     = running & ~(address counter wrap edge) & reg(we_sel & go)
//   counter   : steps DATA_WIDTH/8 per write (19 bits for 2^14 x 128),
//               cleared one cycle after init
//   running   : power-on 1, set two cycles after init, cleared when the
//               counter's top bit toggles (2^NSAMPLES writes done) (Register5)
//   bram_addr = word address, bram_we = write, both one cycle later;
//   bram_data_in = din two cycles later
//   status    = {running, 12'b0..., ~running, byte count} one cycle later:
//               bit 31 running, bit NSAMPLES+log2(DATA_WIDTH/8) ~running,
//               bits below it the byte count of the next write
//   arm_out   = ctrl bit 0
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
// block = 'casper_library_scopes.slx/snapshot'
// deviations = [
//   'The ctrl / status swregs and the bram shared_bram yellow blocks are not implemented: ctrl is an input port (the swreg value), status an output port (the value written into the swreg, before its latency-1 cast_gw register), and bram_addr / bram_data_in / bram_we / bram_data_out are the shared_bram ports before its calc_add address manipulation and munge word reordering.',
//   'Only BRAM storage with offset, circap, value, ext_arm, ext_circ and provide_outputs off is implemented (the bitfield_snapshot configuration of tut_spec); the other options stop elaboration with $fatal. The HDL defaults are these values, while the mask defaults turn offset, circap, value and provide_outputs on.',
// ]
//
// [params.STORAGE]
// mask = 'storage'
// type = 'popup'
// hdl_unsupported = [1]
// [params.STORAGE.values]
// 0 = 'bram'
// 1 = 'dram'
//
// [params.NSAMPLES]
// mask = 'nsamples'
// type = 'edit'
//
// [params.DATA_WIDTH]
// mask = 'data_width'
// type = 'popup'
// [params.DATA_WIDTH.values]
// 8 = '8'
// 16 = '16'
// 32 = '32'
// 64 = '64'
// 128 = '128'
//
// [params.OFFSET]
// mask = 'offset'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.OFFSET.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.CIRCAP]
// mask = 'circap'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.CIRCAP.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.VALUE]
// mask = 'value'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.VALUE.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.EXT_ARM]
// mask = 'ext_arm'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.EXT_ARM.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.EXT_CIRC]
// mask = 'ext_circ'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.EXT_CIRC.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.PROVIDE_OUTPUTS]
// mask = 'provide_outputs'
// type = 'checkbox'
// hdl_unsupported = [1]
// [params.PROVIDE_OUTPUTS.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_DSP48]
// mask = 'use_dsp48'
// type = 'checkbox'
// note = 'implementation only (counter in a DSP48); no effect on the behaviour'
// [params.USE_DSP48.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// IN_WIDTH = 'inherited din width; din is reinterpreted unsigned and cast (zero-extended / truncated) to DATA_WIDTH'
//
// [mask_missing]
// dram_dimm = 'DRAM storage not implemented'
// dram_clock = 'DRAM storage not implemented'
//
// [ports]
// order = 'Simulink: din, we, trig -> arm_out; HDL: clk, din, we, trig, ctrl, bram_data_out -> status, bram_addr, bram_data_in, bram_we, arm_out'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// ctrl = 'value of the swreg <block>/ctrl (From Processor, 32 bits)'
// status = 'value into the swreg <block>/status (To Processor, 32 bits)'
// bram_addr = 'shared_bram <block>/bram addr input (NSAMPLES bits)'
// bram_data_in = 'shared_bram <block>/bram data_in input (DATA_WIDTH bits)'
// bram_we = 'shared_bram <block>/bram we input'
// bram_data_out = 'shared_bram <block>/bram data_out (unused: terminated in Simulink)'
// @simulink-mapping end

module snapshot #(
    parameter int STORAGE         = 0,      // 0 bram, 1 dram (not implemented)
    parameter int NSAMPLES        = 10,     // capture depth 2^NSAMPLES words
    parameter int DATA_WIDTH      = 32,     // 8, 16, 32, 64 or 128
    parameter int OFFSET          = 0,
    parameter int CIRCAP          = 0,
    parameter int VALUE           = 0,
    parameter int EXT_ARM         = 0,
    parameter int EXT_CIRC        = 0,
    parameter int PROVIDE_OUTPUTS = 0,
    parameter int USE_DSP48       = 1,
    parameter int IN_WIDTH        = DATA_WIDTH
)(
    input  logic                  clk,
    input  logic [IN_WIDTH-1:0]   din,
    input  logic                  we,
    input  logic                  trig,
    input  logic [31:0]           ctrl,
    input  logic [DATA_WIDTH-1:0] bram_data_out = '0,
    output logic [31:0]           status,
    output logic [NSAMPLES-1:0]   bram_addr,
    output logic [DATA_WIDTH-1:0] bram_data_in,
    output logic                  bram_we,
    output logic                  arm_out
);

    localparam int INC   = DATA_WIDTH / 8;         // add_gen increment (bytes per word)
    localparam int LINC  = $clog2(INC);
    localparam int CBITS = NSAMPLES + LINC + 1;    // add_gen counter_size

    initial
    begin
        if (STORAGE != 0)
            $fatal(1, "snapshot: DRAM storage is not implemented (STORAGE = %0d)", STORAGE);
        if (OFFSET != 0 || CIRCAP != 0 || VALUE != 0 || EXT_ARM != 0 || EXT_CIRC != 0 || PROVIDE_OUTPUTS != 0)
            $fatal(1, "snapshot: offset / circap / value / ext_arm / ext_circ / provide_outputs are not implemented");
        if (DATA_WIDTH != 8 && DATA_WIDTH != 16 && DATA_WIDTH != 32 && DATA_WIDTH != 64 && DATA_WIDTH != 128)
            $fatal(1, "snapshot: DATA_WIDTH = %0d must be 8, 16, 32, 64 or 128", DATA_WIDTH);
        if (NSAMPLES < 1 || NSAMPLES + LINC > 30)
            $fatal(1, "snapshot: NSAMPLES = %0d out of range (NSAMPLES + log2(DATA_WIDTH/8) <= 30 for the 32-bit status)", NSAMPLES);
    end

    // ── ri / cast: unsigned, zero-extended or truncated to DATA_WIDTH ─────────
    logic [DATA_WIDTH-1:0] din_c;
    assign din_c = DATA_WIDTH'(din);

    // ctrl_split / ctrl_combine with the circ / arm constants 0 pass ctrl
    // through unchanged; arm_out = arm_or = ctrl bit 0
    assign arm_out = ctrl[0];

    // ── basic_ctrl ───────────────────────────────────────────────────────────
    logic [2:0] src_d;                 // {valid_src, trig_src, enable} delayed
    logic       init, trig_sel, we_sel, not_init, trig_ok, armed, go;
    logic       trig_in [2], we_in [2], and_in [2];

    delay #(.LATENCY(1), .BITWIDTH(3)) u_src_dly (.clk(clk), .din(ctrl[2:0]), .dout(src_d));
    edge_detect #(.EDGE(0), .POLARITY(0)) u_init (.clk(clk), .din(src_d[0]), .dout(init));

    assign trig_in = '{trig, 1'b1};
    assign we_in   = '{we, 1'b1};
    multiplexer #(.NBITS(1), .NINPUTS(2), .LATENCY(0)) u_mux2 (
        .clk(clk), .din(trig_in), .sel(src_d[1]), .dout(trig_sel));
    multiplexer #(.NBITS(1), .NINPUTS(2), .LATENCY(0)) u_mux1 (
        .clk(clk), .din(we_in), .sel(src_d[2]), .dout(we_sel));

    inverter #(.NBITS(1), .LATENCY(0)) u_inv (.clk(clk), .din(init), .dout(not_init));
    assign and_in = '{trig_sel, not_init};
    logical #(.NBITS(1), .NINPUTS(2), .LATENCY(0), .FUNC(0)) u_trig_ok (
        .clk(clk), .din(and_in), .dout(trig_ok));

    // Register1: d = 1, rst = trig_ok, en = init
    register #(.BITWIDTH(1), .USE_RST(1), .USE_ENABLE(1), .INIT_VAL(0)) u_armed (
        .clk(clk), .rst(trig_ok), .en(init), .d(1'b1), .q(armed));
    // Register6: d = trig_sel, rst = init, en = armed
    register #(.BITWIDTH(1), .USE_RST(1), .USE_ENABLE(1), .INIT_VAL(0)) u_go (
        .clk(clk), .rst(init), .en(armed), .d(trig_sel), .q(go));

    // ── add_gen ──────────────────────────────────────────────────────────────
    logic             init_d1, init_d2, cont_d, we_go, wrap_bit, wrap_edge, not_wrap, cont_or;
    logic             running, write, running_d, not_running_d;
    logic [CBITS-1:0] count;
    logic [NSAMPLES+LINC-1:0] byte_cnt_d;
    logic [DATA_WIDTH-1:0]    din_d;
    logic             wg_in [2], or_in [2], wr_in [3];

    delay #(.LATENCY(1), .BITWIDTH(1)) u_delay4 (.clk(clk), .din(init), .dout(init_d1));
    delay #(.LATENCY(1), .BITWIDTH(1)) u_delay  (.clk(clk), .din(init_d1), .dout(init_d2));
    delay #(.LATENCY(1), .BITWIDTH(1)) u_delay3 (.clk(clk), .din(1'b0), .dout(cont_d));    // cont = stop = 0

    assign wg_in = '{we_sel, go};
    logical #(.NBITS(1), .NINPUTS(2), .LATENCY(1), .FUNC(0)) u_logical1 (
        .clk(clk), .din(wg_in), .dout(we_go));

    counter #(
        .COUNTER_TYPE(0), .NBITS(CBITS), .COUNT_DIR(0), .INIT_VAL(0), .STEP(INC),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1)
    ) u_add_gen (.clk(clk), .rst(init_d1), .enable(write), .dout(count));

    slice #(.NBITS(CBITS), .START_BIT(NSAMPLES + LINC), .WIDTH(1)) u_slice3 (.din(count), .dout(wrap_bit));
    edge_detect #(.EDGE(2), .POLARITY(0)) u_wrap_edge (.clk(clk), .din(wrap_bit), .dout(wrap_edge));
    inverter #(.NBITS(1), .LATENCY(0)) u_inv1 (.clk(clk), .din(wrap_edge), .dout(not_wrap));
    assign or_in = '{cont_d, not_wrap};
    logical #(.NBITS(1), .NINPUTS(2), .LATENCY(0), .FUNC(2)) u_logical4 (
        .clk(clk), .din(or_in), .dout(cont_or));

    // Register5: power-on 1; d = cont, rst (loads 1) = init two cycles later, en = wrap_edge
    register #(.BITWIDTH(1), .USE_RST(1), .USE_ENABLE(1), .INIT_VAL(1)) u_running (
        .clk(clk), .rst(init_d2), .en(wrap_edge), .d(cont_d), .q(running));

    assign wr_in = '{running, cont_or, we_go};
    logical #(.NBITS(1), .NINPUTS(3), .LATENCY(0), .FUNC(0)) u_logical6 (
        .clk(clk), .din(wr_in), .dout(write));

    delay #(.LATENCY(1), .BITWIDTH(DATA_WIDTH)) u_delay6 (.clk(clk), .din(din_c), .dout(din_d));

    // status = Concat(Shift(Convert(running)), Inverter(running), Delay1(byte count))
    delay #(.LATENCY(1), .BITWIDTH(NSAMPLES + LINC)) u_delay1 (
        .clk(clk), .din(count[NSAMPLES+LINC-1:0]), .dout(byte_cnt_d));
    delay #(.LATENCY(1), .BITWIDTH(1)) u_shift (.clk(clk), .din(running), .dout(running_d));
    inverter #(.NBITS(1), .LATENCY(1)) u_inverter (.clk(clk), .din(running), .dout(not_running_d));
    assign status = {running_d, {(30 - NSAMPLES - LINC){1'b0}}, not_running_d, byte_cnt_d};

    // ── shared_bram inputs: add_del / dat_del / we_del ──────────────────────
    delay #(.LATENCY(1), .BITWIDTH(NSAMPLES))   u_add_del (.clk(clk), .din(count[LINC +: NSAMPLES]), .dout(bram_addr));
    delay #(.LATENCY(1), .BITWIDTH(DATA_WIDTH)) u_dat_del (.clk(clk), .din(din_d), .dout(bram_data_in));
    delay #(.LATENCY(1), .BITWIDTH(1))          u_we_del  (.clk(clk), .din(write), .dout(bram_we));

endmodule
