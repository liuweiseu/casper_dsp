module counter #(
    /* COUNTER_TYPE: free_running or count_limit */
    parameter COUNTER_TYPE = "free_running",
    /* COUNT_TO_VAL: only valid when COUNTER_TYPE is count_limit */
    parameter COUNT_TO_VAL = 0,
    /* COUNTER_DIR: up or down or up/down */
    parameter COUNT_DIR = "up",
    /* INIT_VAL: counter initial value */
    parameter INIT_VAL = 0,
    /* STEP: up or down step */
    parameter STEP = 1,
    /* NBITS: counter bit width */
    parameter NBITS = 8,
    /* BIN_P: binary point*/
    parameter BIN_P = 0,
    /* ENABLE_LOAD: provide load port, 0 or 1 */
    parameter ENABLE_LOAD = 0,
    /* ENABLE_SYNC_RST: provide sync reset port, 0 or 1 */
    parameter ENABLE_SYNC_RST = 0,
    /* ENABLE_ENABLE: provide enable port, 0 or 1 */
    parameter ENABLE_ENABLE = 0
)(
    input clk,
    input rst,
    input enable,
    output [NBITS - 1: 0] dout
);

endmodule

