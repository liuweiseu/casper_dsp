module counter #(
    /* COUNTER_TYPE: free_running or count_limit */
    parameter COUNTER_TYPE = "free_running",
    /* NBITS: counter bit width */
    parameter NBITS = 8,
    /* COUNT_TO_VAL: only valid when COUNTER_TYPE is count_limit */
    parameter [NBITS-1:0] COUNT_TO_VAL = 0,
    /* COUNTER_DIR: up or down or up/down */
    parameter COUNT_DIR = "up",
    /* INIT_VAL: counter initial value */
    parameter [NBITS-1:0] INIT_VAL = '0,
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

/* check the parameters with string type */
initial 
begin
    if (COUNTER_TYPE != "free_running" && COUNTER_TYPE != "count_limit") 
    begin
        $fatal(1, "Error：Invalid 'COUNTER_TYPE - %s'. ", COUNTER_TYPE);
    end
    if (COUNT_DIR != "up" && COUNT_DIR != "down" && COUNT_DIR != "up/down")
    begin
        $fatal(1, "Error：Invalid 'COUNT_DIR - %s'. ", COUNT_DIR);
    end
end

localparam [NBITS-1:0] STEP_VAL = NBITS'(STEP);
logic [ NBITS-1: 0 ] cnt = INIT_VAL;
assign dout = cnt;

generate
    if (COUNTER_TYPE == "free_running") 
    begin: GEN_FREE_RUNNING
        if (COUNT_DIR == "up")
        begin: UP
            always_ff @(posedge clk)
                cnt <= cnt + STEP_VAL;
        end
        else if (COUNT_DIR == "down")
        begin: DOWN
            always_ff @(posedge clk)
                cnt <= cnt - STEP_VAL;
        end
        else if (COUNT_DIR == "up/down")
        begin:  UP_DOWN
            // TODO: what's up/down??
        end
    end
    else if (COUNTER_TYPE == "count_limit") 
    begin: GEN_COUNT_LIMIT
        if (COUNT_DIR == "up")
        begin: UP
            always_ff @(posedge clk)
                begin
                    if (cnt == COUNT_TO_VAL[NBITS-1:0])
                        cnt <= cnt;
                    else
                        cnt <= cnt + STEP_VAL;
                end
        end
        else if (COUNT_DIR == "down")
        begin: DOWN
            always_ff @(posedge clk)
                begin
                    if (cnt == COUNT_TO_VAL[NBITS-1:0])
                        cnt <= cnt;
                    else
                        cnt <= cnt - STEP_VAL;
                end
        end
        else if (COUNT_DIR == "up/down")
        begin:  UP_DOWN
            // TODO: what's up/down??
        end
    end
endgenerate

endmodule

