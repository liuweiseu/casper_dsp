// read_ctrl — read-side controller inside casper_library's xeng_descramble
// (casper_library_correlator.slx, system_456; identical in
// xeng_descramble_4ant, system_973). Not a library block.
//
//   dly    : Counter "ship_element_delay", free running, DEL_BITS bits,
//            rst = start | pace, no enable
//   pace   = (dly >= DEL)                 (Relational1: DEL <= dly, latency 0)
//   enable = pace & ~done
//   rd     : Counter "element", free running, RD_BITS bits, rst = start,
//            en = enable  -> read_addr
//   done   : Register (init 0, rst = start, en = d), d = (rd >= CNT)
//            (Relational3: CNT <= rd, latency 0)
//
// After start the counter steps through the narrow read addresses one every
// DEL+1 cycles (every cycle when DEL = 0) until it reaches CNT; done then
// holds enable low until the next start. The done register must give rst
// priority over en: after a read pass it sits with en = 1, and only the
// reset lets the next start through. At power-on done = 0, so a read pass
// runs without any start (xeng_descramble's spontaneous power-on read).
//
// DEL (ship_el_del), CNT (ship_el_cnt), DEL_BITS and RD_BITS are the
// xeng_descramble mask initialization values.
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
// block = 'casper_library_correlator.slx/xeng_descramble/read_ctrl'
// deviations = []
//
// [hdl_only]
// DEL = 'xeng_descramble mask-init ship_el_del'
// CNT = 'xeng_descramble mask-init ship_el_cnt'
// DEL_BITS = 'xeng_descramble mask-init ship_el_del_bits'
// RD_BITS = 'ceil(log2(ship_el_cnt+1)) of xeng_descramble'
//
// [mask_missing]
//
// [ports]
// note = 'unmasked subsystem (system_456.xml); identical copy in xeng_descramble_4ant (system_973.xml)'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module read_ctrl #(
    parameter int DEL      = 2,
    parameter int CNT      = 288,
    parameter int DEL_BITS = 2,
    parameter int RD_BITS  = 9
)(
    input  logic               clk,
    input  logic               start,
    output logic [RD_BITS-1:0] read_addr,
    output logic               enable
);

    logic [DEL_BITS-1:0] dly, del_c;
    logic [RD_BITS-1:0]  cnt_c;
    logic                pace, at_end, done, dly_rst;

    constant #(.NBITS(DEL_BITS), .VAL(DEL)) u_del (.out(del_c));
    constant #(.NBITS(RD_BITS), .VAL(CNT)) u_cnt_c (.out(cnt_c));

    // pace = (DEL <= dly)
    relational #(.NBITS(DEL_BITS), .COMP(4), .LATENCY(0), .SIGNED(0)) u_pace (
        .clk(clk), .a(del_c), .b(dly), .out(pace));

    assign dly_rst = start | pace;
    counter #(
        .COUNTER_TYPE(0), .NBITS(DEL_BITS), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0), .RST_VAL(0)
    ) u_dly (.clk(clk), .rst(dly_rst), .enable(1'b1), .dout(dly));

    assign enable = pace & ~done;
    counter #(
        .COUNTER_TYPE(0), .NBITS(RD_BITS), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_rd (.clk(clk), .rst(start), .enable(enable), .dout(read_addr));

    // at_end = (CNT <= rd)
    relational #(.NBITS(RD_BITS), .COMP(4), .LATENCY(0), .SIGNED(0)) u_at_end (
        .clk(clk), .a(cnt_c), .b(read_addr), .out(at_end));

    register #(.BITWIDTH(1), .USE_RST(1), .USE_ENABLE(1), .INIT_VAL(0)) u_done (
        .clk(clk), .rst(start), .en(at_end), .d(at_end), .q(done));

endmodule
