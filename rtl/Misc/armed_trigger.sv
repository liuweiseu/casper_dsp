module armed_trigger (
    input  logic clk,
    input  logic arm,
    input  logic trig_in,
    output logic trig_out
);

    logic arm_edge;   // rising-edge pulse on arm (active high)
    logic q_out;      // register output
    logic trig_out_w; // internal wire for trig_out, also fed back to register.en

    // Detect rising edge of arm; output is active high for one cycle
    edge_detect #(
        .EDGE_TYPE  (0),   // rising edge
        .OUTPUT_POL (0)    // active high
    ) u_edge_detect (
        .clk  (clk),
        .din  (arm),
        .dout (arm_edge)
    );

    // Register: d=0, en=trig_out, rst=arm_edge (synchronous reset to 1 = "armed")
    register #(
        .BITWIDTH   (1),
        .USE_RST    (1),
        .USE_ENABLE (1),
        .INIT_VAL   (1)
    ) u_register (
        .clk (clk),
        .rst (arm_edge),
        .en  (trig_out_w),
        .d   (1'b0),
        .q   (q_out)
    );

    // AND(trig_in, q_out) — combinational (LATENCY=0)
    logic [0:0] and_din [2];
    assign and_din[0] = trig_in;
    assign and_din[1] = q_out;

    logical #(
        .NBITS   (1),
        .NINPUTS (2),
        .LATENCY (0),
        .FUNC    (0)   // AND
    ) u_logical (
        .clk  (clk),
        .din  (and_din),
        .dout (trig_out_w)
    );

    assign trig_out = trig_out_w;

endmodule
