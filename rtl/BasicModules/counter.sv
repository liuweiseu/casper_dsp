module counter #(
    /* COUNTER_TYPE: 0=free_running, 1=count_limit */
    parameter int COUNTER_TYPE = 0,
    /* NBITS: counter bit width */
    parameter NBITS = 8,
    /* COUNT_TO_VAL: only valid when COUNTER_TYPE is count_limit */
    parameter int COUNT_TO_VAL = 0,
    /* COUNT_DIR: 0=up, 1=down, 2=up_down */
    parameter int COUNT_DIR = 0,
    /* INIT_VAL: counter initial value */
    parameter int INIT_VAL = 0,
    /* STEP: up or down step */
    parameter int STEP = 1,
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
logic [NBITS-1:0] cnt;
initial cnt = INIT_VAL_;
assign dout = cnt;

generate
    if (COUNTER_TYPE == FREE_RUNNING)
    begin: GEN_FREE_RUNNING
        if (COUNT_DIR == DIR_UP)
        begin: UP
            always_ff @(posedge clk)
                cnt <= cnt + STEP_VAL;
        end
        else if (COUNT_DIR == DIR_DOWN)
        begin: DOWN
            always_ff @(posedge clk)
                cnt <= cnt - STEP_VAL;
        end
        else if (COUNT_DIR == DIR_UP_DOWN)
        begin:  UP_DOWN
            // TODO: what's up/down??
        end
    end
    else if (COUNTER_TYPE == COUNT_LIMIT)
    begin: GEN_COUNT_LIMIT
        if (COUNT_DIR == DIR_UP)
        begin: UP
            always_ff @(posedge clk)
                begin
                    if (cnt == NBITS'(COUNT_TO_VAL))
                        cnt <= cnt;
                    else
                        cnt <= cnt + STEP_VAL;
                end
        end
        else if (COUNT_DIR == DIR_DOWN)
        begin: DOWN
            always_ff @(posedge clk)
                begin
                    if (cnt == NBITS'(COUNT_TO_VAL))
                        cnt <= cnt;
                    else
                        cnt <= cnt - STEP_VAL;
                end
        end
        else if (COUNT_DIR == DIR_UP_DOWN)
        begin:  UP_DOWN
            // TODO: what's up/down??
        end
    end
endgenerate

endmodule
