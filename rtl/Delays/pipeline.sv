// pipeline — plain register pipeline (no reset, no enable)
//
// dout = din delayed by LATENCY clock cycles. A thin wrapper around
// delay_srl with reset and enable disabled, whose parameter name follows
// casper_library's delays/pipeline block (LATENCY). LATENCY = 0 is a
// combinational pass-through. All stages power up to 0.

module pipeline #(
    parameter int BITWIDTH = 8,
    parameter int LATENCY  = 1
)(
    input  logic                clk,
    input  logic [BITWIDTH-1:0] din,
    output logic [BITWIDTH-1:0] dout
);

    delay_srl #(
        .BITWIDTH  (BITWIDTH),
        .DELAY_LEN (LATENCY),
        .USE_ENABLE(0),
        .USE_RST   (0)
    ) u_delay_srl (
        .clk (clk),
        .rst (1'b0),
        .en  (1'b1),
        .din (din),
        .dout(dout)
    );

endmodule
