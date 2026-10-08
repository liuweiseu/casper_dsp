// counter — Xilinx System Generator Counter block (xbsIndex_r4 "Counter";
// behaviour per the Sysgen block model data/sysgen/block_models/xlCounter.sgm)
//
// Per clock edge, in priority order:
//   rst (ENABLE_SYNC_RST)                    cnt <= RST_VAL
//   enable (ENABLE_ENABLE; else always on):
//     count limited and cnt == COUNT_TO_VAL  cnt <= INIT_VAL
//     load (ENABLE_LOAD)                     cnt <= din
//     otherwise                              cnt <= cnt +/- STEP
// The direction is fixed by COUNT_DIR = 0 (up) / 1 (down); COUNT_DIR = 2
// (Up/Down) takes it from the up port (1 = up, 0 = down) each cycle.
// Power-on value is INIT_VAL.
//
// Mask mapping: cnt_type -> COUNTER_TYPE, n_bits -> NBITS, cnt_to ->
// COUNT_TO_VAL, operation -> COUNT_DIR, start_count -> INIT_VAL (and
// RST_VAL), cnt_by_val -> STEP, load_pin / rst / en -> ENABLE_LOAD /
// ENABLE_SYNC_RST / ENABLE_ENABLE. INIT_VAL, STEP, COUNT_TO_VAL and din are
// raw two's complement / unsigned bit patterns; the binary point and the
// signedness only change how the bits are read, not the counting.
// Ports whose option is off are ignored; load, din and up have default
// values, so instances that do not use them may leave them unconnected.
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
// block = 'xbsIndex_r4.slx/Counter'
// deviations = [
//   'start_count, cnt_by_val and cnt_to are real values that xlCounter.sgm quantizes to {arith_type, n_bits, bin_pt} with Truncate/Wrap (count_reg_xfix_cell, step_xfix, initial_value_xfix); the HDL takes INIT_VAL, STEP, COUNT_TO_VAL as raw integers, so with bin_pt > 0 multiply by 2^bin_pt (counter.sv:17-19,78-79,95).',
//   "The mask default cnt_to = 'Inf' has no HDL equivalent (HDL default COUNT_TO_VAL = 0); it is only relevant for Count Limited, where cnt_to must be given as a finite raw value.",
//   'Priority matches xlCounter.sgm (rst or count-limit hit -> start_count, else en: load -> din, else +/- step; the limit compare is only evaluated while en = 1); the HDL lets RST_VAL differ from INIT_VAL, which Sysgen cannot.',
//   "din is loaded as a raw bit pattern; Simulink assigns din into the counter type, so din must already have the counter's n_bits/bin_pt/signedness to be bit-exact.",
//   "The Up/Down mode is unverified against Simulink: xlCounter.sgm itself carries 'TODO: Address bug in 2nd half of xlcounter_tb (up/down counter)'.",
// ]
//
// [params.COUNTER_TYPE]
// mask = 'cnt_type'
// type = 'popup'
// note = 'xlCounter.sgm encodes these as 1 / 2'
// [params.COUNTER_TYPE.values]
// 0 = 'Free Running'
// 1 = 'Count Limited'
//
// [params.NBITS]
// mask = 'n_bits'
// type = 'edit'
//
// [params.COUNT_TO_VAL]
// mask = 'cnt_to'
// type = 'edit'
// note = 'raw bit pattern in the HDL; real value in Simulink'
//
// [params.COUNT_DIR]
// mask = 'operation'
// type = 'popup'
// [params.COUNT_DIR.values]
// 0 = 'Up'
// 1 = 'Down'
// 2 = 'Up/Down'
//
// [params.INIT_VAL]
// mask = 'start_count'
// type = 'edit'
// note = 'raw bit pattern in the HDL; real value in Simulink'
//
// [params.STEP]
// mask = 'cnt_by_val'
// type = 'edit'
// note = 'raw bit pattern in the HDL; real value in Simulink'
//
// [params.BIN_P]
// mask = 'bin_pt'
// type = 'edit'
// note = 'interpretation only in the HDL'
//
// [params.ENABLE_LOAD]
// mask = 'load_pin'
// type = 'checkbox'
// [params.ENABLE_LOAD.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.ENABLE_SYNC_RST]
// mask = 'rst'
// type = 'checkbox'
// [params.ENABLE_SYNC_RST.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.ENABLE_ENABLE]
// mask = 'en'
// type = 'checkbox'
// [params.ENABLE_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// RST_VAL = 'HDL extension: reset value separate from start_count (defaults to INIT_VAL, which is what Sysgen does)'
//
// [mask_missing]
// arith_type = 'signedness only changes how the bits are read; counting is bit-identical'
// explicit_period = 'sample period has no HDL meaning'
// period = 'sample period has no HDL meaning'
// use_behavioral_HDL = 'implementation style only'
// implementation = 'Fabric / DSP48 resource choice only'
//
// [ports]
// order = 'HDL: rst, enable, load, din, up. Simulink shows only the enabled optional ports; casper sync_delay (system_237.xml, Counter 237:6 with load_pin+en) wires load=in1, din=in2, en=in3'
// note = 'Output port 1 is unlabelled in the Sysgen icon; maps to dout. HDL rst/enable have no default and must be tied off when the option is off'
// [ports.renamed]
// enable = 'en'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module counter #(
    /* COUNTER_TYPE: 0=free_running, 1=count_limit */
    parameter int COUNTER_TYPE = 0,
    /* NBITS: counter bit width */
    parameter int NBITS = 8,
    /* COUNT_TO_VAL: only valid when COUNTER_TYPE is count_limit */
    parameter int COUNT_TO_VAL = 0,
    /* COUNT_DIR: 0=up, 1=down, 2=up_down (direction from the up port) */
    parameter int COUNT_DIR = 0,
    /* INIT_VAL: power-on value, and the value loaded after reaching
       COUNT_TO_VAL (Xilinx start_count) */
    parameter int INIT_VAL = 0,
    /* STEP: up or down step */
    parameter int STEP = 1,
    /* BIN_P: binary point; interpretation only, does not change the logic */
    parameter int BIN_P = 0,
    /* ENABLE_LOAD: provide load/din ports (1=enabled) */
    parameter int ENABLE_LOAD = 0,
    /* ENABLE_SYNC_RST: synchronous reset to RST_VAL when rst=1 (1=enabled) */
    parameter int ENABLE_SYNC_RST = 0,
    /* ENABLE_ENABLE: gate counting, wrapping and loading on enable (1=enabled) */
    parameter int ENABLE_ENABLE = 0,
    /* RST_VAL: value loaded by the synchronous reset. The Xilinx Counter
       resets to start_count (xlCounter.sgm), so the default is INIT_VAL;
       set it only to model a reset value that differs from start_count. */
    parameter int RST_VAL = INIT_VAL
)(
    input              clk,
    input              rst,
    input              enable,
    input              load = 1'b0,
    input  [NBITS-1:0] din = '0,
    input              up = 1'b1,
    output [NBITS-1:0] dout
);

localparam int FREE_RUNNING = 0;
localparam int COUNT_LIMIT  = 1;
localparam int DIR_UP       = 0;
localparam int DIR_DOWN     = 1;
localparam int DIR_UP_DOWN  = 2;

/* check the parameters */
initial
begin
    if (COUNTER_TYPE != FREE_RUNNING && COUNTER_TYPE != COUNT_LIMIT)
    begin
        $fatal(1, "Error: Invalid COUNTER_TYPE = %0d. (0=free_running, 1=count_limit)", COUNTER_TYPE);
    end
    if (COUNT_DIR != DIR_UP && COUNT_DIR != DIR_DOWN && COUNT_DIR != DIR_UP_DOWN)
    begin
        $fatal(1, "Error: Invalid COUNT_DIR = %0d. (0=up, 1=down, 2=up_down)", COUNT_DIR);
    end
end

localparam [NBITS-1:0] STEP_VAL  = NBITS'(STEP);
localparam [NBITS-1:0] INIT_VAL_ = NBITS'(INIT_VAL);
localparam [NBITS-1:0] RST_VAL_  = NBITS'(RST_VAL);
// Power-on value is given as a declaration initializer rather than an
// 'initial' block: newer Verilator rejects a variable written by both an
// 'initial' process and an always_ff (MULTIDRIVEN).
logic [NBITS-1:0] cnt = INIT_VAL_;
assign dout = cnt;

logic count_up;
assign count_up = (COUNT_DIR == DIR_UP_DOWN) ? up : (COUNT_DIR == DIR_UP);

always_ff @(posedge clk)
    if (ENABLE_SYNC_RST != 0 && rst)
        cnt <= RST_VAL_;
    else if (ENABLE_ENABLE == 0 || enable)
    begin
        if (COUNTER_TYPE == COUNT_LIMIT && cnt == NBITS'(COUNT_TO_VAL))
            cnt <= INIT_VAL_;
        else if (ENABLE_LOAD != 0 && load)
            cnt <= din;
        else if (count_up)
            cnt <= cnt + STEP_VAL;
        else
            cnt <= cnt - STEP_VAL;
    end

endmodule
