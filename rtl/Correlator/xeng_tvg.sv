// xeng_tvg — casper_library X-engine test vector generator
// (casper_library_correlator.slx, Block SID 717; no _init.m, the mask
// parameters are referenced directly by the diagram in system_717.xml)
//
// A 4:1 source in front of an X-engine input:
//
//   tvg_sel  data_out
//     0      data_in (pass-through)
//     1      {c, ~c, c, ~c}, four 4-bit fields, c = antenna count
//     2      constant {0.1, -0.75, 0.5, -0.25} as Fix_4_3 = 16'h1A4E
//     3      tv[k][15:0] for antenna k = 0..7 (repeating)
//   For tvg_sel != 0 sync and valid are generated internally too.
//
// Diagram (Xilinx Mux: input 1 = sel, then d0, d1, ...):
//   use_tvg  = Delay(tvg_sel != 0 (Relational, latency 1), 1)
//   sync_int = use_tvg ? edge2 : sync                          (Mux4, latency 0)
//   edge2    = edge_detect(Both)(Counter4[SYNC_PERIOD]); Counter4 free
//              running, SYNC_PERIOD+1 bits, start 2^SYNC_PERIOD - 2: first
//              pulse at t = 2, then every 2^SYNC_PERIOD cycles
//   ant_en   = edge_detect(Both)(Counter[X_INT_BITS]); Counter free running,
//              X_INT_BITS+1 bits, rst = sync_int: one pulse every
//              2^X_INT_BITS cycles
//   rst_d    = Delay(sync_int, 1)
//   Counter1 4-bit up, Counter2 3-bit up, Counter3 4-bit down from 15, all
//              free running, rst = rst_d (reset to the start value), en = ant_en
//   Concat1  = {Counter1, Counter3, Counter1, Counter3} ─ Delay(1) ─ d1
//   Concat2  = the four Fix_4_3 constants reinterpreted as UFix_4_0     ─ d2
//   Mux2 (8:1, latency 1, sel = Counter2) of tv0..tv7 [15:0]          ─ d3
//   Delay(data_in, 2)                                                  ─ d0
//   data_out = Mux3 (4:1, latency 1, sel = Delay(tvg_sel, 1))
//   valid_out = Delay(use_tvg ? 1 : valid_in, 3)     (Mux1 latency 0, 3 Delays)
//   sync_out  = Delay(rst_d, 2)                       (= sync_int delayed 3)
//
// Resolved: Sysgen's Constant quantizes 0.1 to Fix_4_3 by rounding: the
// stored block (Constant7) shows the quantized value 0.125 on its icon, i.e.
// 4'b0001, so the mode-2 word is 16'h1A4E (not 16'h0A4E).
// Counter3 resets and starts at 15 (Xilinx start_count): counter RST_VAL.
// Reset has priority over enable in Counter1..3: when sync_int resets
// Counter while its MSB is 1, the falling edge makes a spurious ant_en one
// cycle later, which rst_d swallows.
//
// tv0..tv7 are xps software registers (32-bit, From Processor) in the
// library; here they are a 8 x 32-bit input port, tv[k] = register k, of
// which only [15:0] is used.
//
// Parameters (mask names, stored defaults): ANT_BITS 2 (not referenced by
// the diagram: declared only; the antenna counters are fixed at 3/4 bits),
// X_INT_BITS 5, SYNC_PERIOD 15. DATA_WIDTH (width of data_in, inherited in
// Simulink) is not a mask parameter; the full-precision Mux3 makes data_out
// max(DATA_WIDTH, 16) bits, data_in taken as unsigned (zero-extended).
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
// block = 'casper_library_correlator.slx/xeng_tvg'
// deviations = [
//   "tv0..tv7 are an input port instead of internal xps software registers (32-bit, From Processor, io_delay 0). The library diagram drives their simulation ports from Constants 0, 4369, 4369*2 .. 4369*7 (system_717.xml Constant, Constant1, Constant2, Constant8..Constant12). To reproduce Simulink, drive tv[k] = 16'h1111*k; only tv[k][15:0] is used (Slice nbits 16).",
//   "DATA_WIDTH makes data_in's inherited type explicit, and the HDL treats data_in as unsigned with binary point 0, zero-extended to max(DATA_WIDTH,16). Mux3 (system_717.xml) is Full precision, so in Simulink a signed or fractional data_in changes data_out's type: other inputs are sign-extended or shifted to align binary points.",
//   'ANT_BITS is declared only. The diagram does not reference it either: the antenna counters are fixed at 3/4 bits.',
// ]
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from the input signal (data_in)'
// OUT_WIDTH = 'derived from other parameters (do not override)'
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// tv = 'the software registers tv0..tv7 of the diagram, as an input port'
// @simulink-mapping end

module xeng_tvg #(
    parameter int ANT_BITS    = 2,
    parameter int X_INT_BITS  = 5,
    parameter int SYNC_PERIOD = 15,
    parameter int DATA_WIDTH  = 16,
    // derived; not to be overridden
    parameter int OUT_WIDTH   = (DATA_WIDTH > 16) ? DATA_WIDTH : 16
)(
    input  logic                 clk,
    input  logic [1:0]           tvg_sel,
    input  logic                 sync,
    input  logic [DATA_WIDTH-1:0] data_in,
    input  logic                 valid_in,
    input  logic [7:0][31:0]     tv,
    output logic                 sync_out,
    output logic [OUT_WIDTH-1:0] data_out,
    output logic                 valid_out
);

    initial begin
        if (X_INT_BITS < 1 || SYNC_PERIOD < 1)
            $fatal(1, "xeng_tvg: X_INT_BITS and SYNC_PERIOD must be >= 1");
        if (OUT_WIDTH != ((DATA_WIDTH > 16) ? DATA_WIDTH : 16))
            $fatal(1, "xeng_tvg: OUT_WIDTH is derived, do not override");
    end

    // ── mode select ──────────────────────────────────────────────────────────
    logic [1:0] zero2, sel_d;
    logic       tvg_on, use_tvg;

    constant #(.NBITS(2), .VAL(0)) u_zero2 (.out(zero2));
    relational #(.NBITS(2), .COMP(1), .LATENCY(1), .SIGNED(0)) u_rel (
        .clk(clk), .a(tvg_sel), .b(zero2), .out(tvg_on));
    delay #(.LATENCY(1), .BITWIDTH(1)) u_delay10 (.clk(clk), .din(tvg_on), .dout(use_tvg));
    delay #(.LATENCY(1), .BITWIDTH(2)) u_delay6 (.clk(clk), .din(tvg_sel), .dout(sel_d));

    // ── internal sync ────────────────────────────────────────────────────────
    logic [SYNC_PERIOD:0] cnt4;
    logic                 edge2, sync_int, rst_d;

    counter #(
        .COUNTER_TYPE(0), .NBITS(SYNC_PERIOD + 1), .COUNT_DIR(0),
        .INIT_VAL((1 << SYNC_PERIOD) - 2), .STEP(1), .ENABLE_SYNC_RST(0), .ENABLE_ENABLE(0)
    ) u_counter4 (.clk(clk), .rst(1'b0), .enable(1'b1), .dout(cnt4));

    edge_detect #(.EDGE(2), .POLARITY(0)) u_edge2 (
        .clk(clk), .din(cnt4[SYNC_PERIOD]), .dout(edge2));

    logic [0:0] sync_mux_in [2];
    logic [0:0] sync_mux_out;
    assign sync_mux_in[0] = sync;
    assign sync_mux_in[1] = edge2;
    multiplexer #(.NBITS(1), .NINPUTS(2), .LATENCY(0)) u_mux4 (
        .clk(clk), .din(sync_mux_in), .sel(use_tvg), .dout(sync_mux_out));
    assign sync_int = sync_mux_out[0];

    delay #(.LATENCY(1), .BITWIDTH(1)) u_delay8 (.clk(clk), .din(sync_int), .dout(rst_d));

    // ── antenna counters ─────────────────────────────────────────────────────
    logic [X_INT_BITS:0] cnt;
    logic                ant_en;
    logic [3:0]          c1, c3;
    logic [2:0]          c2;

    counter #(
        .COUNTER_TYPE(0), .NBITS(X_INT_BITS + 1), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0), .RST_VAL(0)
    ) u_counter (.clk(clk), .rst(sync_int), .enable(1'b1), .dout(cnt));

    edge_detect #(.EDGE(2), .POLARITY(0)) u_ant_edge (
        .clk(clk), .din(cnt[X_INT_BITS]), .dout(ant_en));

    counter #(
        .COUNTER_TYPE(0), .NBITS(4), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_counter1 (.clk(clk), .rst(rst_d), .enable(ant_en), .dout(c1));

    counter #(
        .COUNTER_TYPE(0), .NBITS(3), .COUNT_DIR(0), .INIT_VAL(0), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(0)
    ) u_counter2 (.clk(clk), .rst(rst_d), .enable(ant_en), .dout(c2));

    counter #(
        .COUNTER_TYPE(0), .NBITS(4), .COUNT_DIR(1), .INIT_VAL(15), .STEP(1),
        .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(1), .RST_VAL(15)
    ) u_counter3 (.clk(clk), .rst(rst_d), .enable(ant_en), .dout(c3));

    // ── data sources ─────────────────────────────────────────────────────────
    logic [DATA_WIDTH-1:0] data_d;
    logic [15:0]           concat1_d, concat2, tv_sel_out;

    delay #(.LATENCY(2), .BITWIDTH(DATA_WIDTH)) u_delay2 (.clk(clk), .din(data_in), .dout(data_d));
    delay #(.LATENCY(1), .BITWIDTH(16)) u_delay4 (
        .clk(clk), .din({c1, c3, c1, c3}), .dout(concat1_d));

    // {0.1 -> 0.125, -0.75, 0.5, -0.25} as Fix_4_3, reinterpreted UFix_4_0
    constant #(.NBITS(16), .VAL(32'h1A4E)) u_concat2 (.out(concat2));

    logic [15:0] tv_in [8];
    for (genvar k = 0; k < 8; k++) begin : GEN_TV
        assign tv_in[k] = tv[k][15:0];
    end
    multiplexer #(.NBITS(16), .NINPUTS(8), .LATENCY(1)) u_mux2 (
        .clk(clk), .din(tv_in), .sel(c2), .dout(tv_sel_out));

    logic [OUT_WIDTH-1:0] mux3_in [4];
    assign mux3_in[0] = OUT_WIDTH'(data_d);
    assign mux3_in[1] = OUT_WIDTH'(concat1_d);
    assign mux3_in[2] = OUT_WIDTH'(concat2);
    assign mux3_in[3] = OUT_WIDTH'(tv_sel_out);
    multiplexer #(.NBITS(OUT_WIDTH), .NINPUTS(4), .LATENCY(1)) u_mux3 (
        .clk(clk), .din(mux3_in), .sel(sel_d), .dout(data_out));

    // ── valid / sync out ─────────────────────────────────────────────────────
    logic [0:0] valid_mux_in [2];
    logic [0:0] valid_mux_out;
    assign valid_mux_in[0] = valid_in;
    assign valid_mux_in[1] = 1'b1;
    multiplexer #(.NBITS(1), .NINPUTS(2), .LATENCY(0)) u_mux1 (
        .clk(clk), .din(valid_mux_in), .sel(use_tvg), .dout(valid_mux_out));
    delay #(.LATENCY(3), .BITWIDTH(1)) u_valid_dly (
        .clk(clk), .din(valid_mux_out[0]), .dout(valid_out));

    delay #(.LATENCY(2), .BITWIDTH(1)) u_sync_dly (.clk(clk), .din(rst_d), .dout(sync_out));

endmodule
