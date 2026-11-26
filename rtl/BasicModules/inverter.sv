// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Inverter'
// deviations = []
//
// [params.USE_ENABLE]
// mask = 'en'
// type = 'checkbox'
// [params.USE_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// NBITS = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
//
// [ports]
// note = 'The Sysgen block icon carries no port labels, so ports map by position (no rename recorded); xlInverter.sgm signature inverter(ip, en) -> op'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module inverter #(
    parameter int NBITS   = 8,
    /* LATENCY: 0 = combinational output, >=1 = pipeline stages (Xilinx default 1) */
    parameter int LATENCY = 1,
    /* USE_ENABLE: 1 = use the enable port en (Xilinx "Provide enable port"):
       en = 0 holds the pipeline registers; no effect when LATENCY = 0.
       en defaults to 1 and may be left unconnected when unused. */
    parameter int USE_ENABLE = 0
)(
    input  logic             clk,
    input  logic             en = 1'b1,
    input  logic [NBITS-1:0] din,
    output logic [NBITS-1:0] dout
);

    logic [NBITS-1:0] result;
    assign result = ~din;

    generate
        if (LATENCY == 0) begin : GEN_COMB
            assign dout = result;
        end else begin : GEN_PIPE
            // Power-on value is given as a declaration initializer and the loop
            // variable is local to the always_ff: newer Verilator rejects a
            // variable written by both an 'initial' process and an always_ff
            // (MULTIDRIVEN).
            logic [NBITS-1:0] shift_reg [0:LATENCY-1] = '{default: '0};
            always_ff @(posedge clk) if (USE_ENABLE == 0 || en) begin
                shift_reg[0] <= result;
                for (int k = 1; k < LATENCY; k = k + 1)
                    shift_reg[k] <= shift_reg[k-1];
            end
            assign dout = shift_reg[LATENCY-1];
        end
    endgenerate

endmodule
