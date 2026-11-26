// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Mux'
// deviations = [
//   "sel >= NINPUTS (possible when NINPUTS is not a power of two) is a Simulink simulation error (xlMux.sgm: 'Value on the selection line exceeds the number of ports'); the HDL reads din[sel] out of range (X in 4-state simulators, 0 in Verilator) without an error.",
//   'Full precision in Simulink merges input types (different widths / binary points / signedness are aligned and extended); the HDL requires all inputs to share NBITS and format. User Defined precision with quantization/overflow (xlMux.sgm: xfix(...) when precision == 2) is not implemented.',
//   'xlMux.sgm has a copy-paste bug: the sel == 23 branch is repeated and the sel == 24 branch is missing, so a Simulink Mux with >= 25 inputs errors (and outputs d0) for sel = 24, whereas the HDL outputs din[24].',
// ]
//
// [params.NINPUTS]
// mask = 'inputs'
// type = 'popup'
// note = 'popup option text is the input count itself; HDL also accepts NINPUTS = 1 or > 32, which the mask cannot express'
// [params.NINPUTS.values]
// 2 = '2'
// 3 = '3'
// 4 = '4'
// 5 = '5'
// 6 = '6'
// 7 = '7'
// 8 = '8'
// 9 = '9'
// 10 = '10'
// 11 = '11'
// 12 = '12'
// 13 = '13'
// 14 = '14'
// 15 = '15'
// 16 = '16'
// 17 = '17'
// 18 = '18'
// 19 = '19'
// 20 = '20'
// 21 = '21'
// 22 = '22'
// 23 = '23'
// 24 = '24'
// 25 = '25'
// 26 = '26'
// 27 = '27'
// 28 = '28'
// 29 = '29'
// 30 = '30'
// 31 = '31'
// 32 = '32'
//
// [params.USE_ENABLE]
// mask = 'en'
// type = 'checkbox'
// [params.USE_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// NBITS = 'inherited width: Simulink takes it from the data inputs'
//
// [mask_missing]
// precision = 'only Full precision is implemented'
// arith_type = 'User Defined output type not implemented'
// n_bits = 'User Defined output type not implemented'
// bin_pt = 'User Defined output type not implemented'
// quantization = 'User Defined output type not implemented'
// overflow = 'User Defined output type not implemented'
//
// [ports]
// order = "Simulink: sel, d0..d{N-1}, [en] (icon port_label input 1 = 'sel'); HDL: en, din[], sel"
// note = 'din[i] folds Simulink d<i>; output unlabelled (xlMux.sgm returns y)'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module multiplexer #(
    parameter int NBITS   = 8,
    parameter int NINPUTS = 2,
    /* LATENCY: 0 = combinational output, >=1 = pipeline stages */
    parameter int LATENCY = 1,
    /* USE_ENABLE: 1 = use the enable port en (Xilinx "Provide enable port"):
       en = 0 holds the pipeline registers; no effect when LATENCY = 0.
       en defaults to 1 and may be left unconnected when unused. */
    parameter int USE_ENABLE = 0
)(
    input  logic                             clk,
    input  logic                             en = 1'b1,
    input  logic [NBITS-1:0]                 din [NINPUTS],
    input  logic [$clog2(NINPUTS)-1:0]       sel,
    output logic [NBITS-1:0]                 dout
);

    logic [NBITS-1:0] result;

    always_comb begin
        result = din[sel];
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
