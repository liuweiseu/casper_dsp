// pipeline — plain register pipeline (no reset, no enable)
//
// dout = din delayed by CSP_LATENCY clock cycles. A thin wrapper around
// delay_srl with reset and enable disabled, whose parameter name follows
// casper_library's delays/pipeline block (CSP_LATENCY). CSP_LATENCY = 0 is a
// combinational pass-through. All stages power up to 0.
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
// block = 'casper_library_delays.slx/pipeline'
// deviations = []
//
// [hdl_only]
// BITWIDTH = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// din = 'd'
// dout = 'q'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module pipeline #(
    parameter int BITWIDTH    = 8,
    parameter int CSP_LATENCY = 1
)(
    input  logic                clk,
    input  logic [BITWIDTH-1:0] din,
    output logic [BITWIDTH-1:0] dout
);

    delay_srl #(
        .BITWIDTH  (BITWIDTH),
        .DELAY_LEN (CSP_LATENCY),
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
