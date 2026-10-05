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
