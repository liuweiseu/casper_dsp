// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Logical'
// deviations = [
//   'All inputs must have the same NBITS and format: Simulink Full precision aligns binary points (align_bp) and extends inputs of different widths/signedness before the bitwise operation; the HDL has no width/type parameters per input.',
//   'User Defined precision (precision/arith_type/n_bits/bin_pt) is not implemented; the HDL output is always the input-width bitwise result.',
//   'No Sysgen .sgm model exists for Logical (data/sysgen/block_models has none); behaviour is taken from the mask description, so latency/en/power-on (0) equivalence is assumed from the sibling Inverter model.',
// ]
//
// [params.FUNC]
// mask = 'logical_function'
// type = 'popup'
// [params.FUNC.values]
// 0 = 'AND'
// 1 = 'NAND'
// 2 = 'OR'
// 3 = 'NOR'
// 4 = 'XOR'
// 5 = 'XNOR'
//
// [params.NINPUTS]
// mask = 'inputs'
// type = 'edit'
//
// [params.USE_ENABLE]
// mask = 'en'
// type = 'checkbox'
// [params.USE_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// NBITS = 'inherited width: Simulink takes it from the input signals'
//
// [mask_missing]
// precision = 'only Full precision is implemented'
// arith_type = 'User Defined output type not implemented (Full precision only)'
// n_bits = 'User Defined output type not implemented (Full precision only)'
// bin_pt = 'User Defined output type not implemented (Full precision only)'
// align_bp = 'HDL assumes all inputs share one format (binary points already aligned)'
//
// [ports]
// note = 'din[i] folds Simulink inputs 1..NINPUTS (d0..d{N-1}); output and inputs are unlabelled in the Sysgen icon. en is the last Simulink input when enabled'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module logical #(
    parameter int NBITS   = 8,
    parameter int NINPUTS = 2,
    parameter int LATENCY = 1,
    /* FUNC: 0=AND, 1=NAND, 2=OR, 3=NOR, 4=XOR, 5=XNOR */
    parameter int FUNC    = 0,
    /* USE_ENABLE: 1 = use the enable port en (Xilinx "Provide enable port"):
       en = 0 holds the pipeline registers; no effect when LATENCY = 0.
       en defaults to 1 and may be left unconnected when unused. */
    parameter int USE_ENABLE = 0
)(
    input  logic             clk,
    input  logic             en = 1'b1,
    input  logic [NBITS-1:0] din [NINPUTS],
    output logic [NBITS-1:0] dout
);

    logic [NBITS-1:0] acc;
    logic [NBITS-1:0] result;

    always_comb begin
        acc = din[0];
        for (int i = 1; i < NINPUTS; i++) begin
            if      (FUNC == 0 || FUNC == 1) acc = acc & din[i];
            else if (FUNC == 2 || FUNC == 3) acc = acc | din[i];
            else                             acc = acc ^ din[i];
        end
        result = (FUNC == 1 || FUNC == 3 || FUNC == 5) ? ~acc : acc;
    end

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
