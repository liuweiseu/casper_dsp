// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Register'
// deviations = [
//   "Simulink converts 'init' (a real value) to the type of d with Round and Saturate (xlRegister.sgm: xtype({..., xlRound, xlSaturate}, init)); the HDL loads BITWIDTH'(INIT_VAL) as a raw, wrapped integer, so pass round(init*2^bin_pt) saturated to the type of d (register.sv:20,26).",
// ]
//
// [params.INIT_VAL]
// mask = 'init'
// type = 'edit'
// note = 'raw bit pattern in the HDL; real value in Simulink'
//
// [params.USE_RST]
// mask = 'rst'
// type = 'checkbox'
// [params.USE_RST.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_ENABLE]
// mask = 'en'
// type = 'checkbox'
// [params.USE_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// BITWIDTH = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
//
// [ports]
// order = 'Simulink: d, rst, en (xlRegister.sgm signature; window_delay system_240 wires Register 240:6 in1=d, in2=rst, in3=en); HDL: rst, en, d'
// note = 'icon port_label d / q match the HDL; HDL rst and en have no default and must be tied off when unused'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module register #(
    /* BITWIDTH: data bit width */
    parameter BITWIDTH   = 1,
    /* USE_RST: 1 = use synchronous reset (rst pin active), 0 = no reset pin
       (Xilinx Register default: off) */
    parameter USE_RST    = 0,
    /* USE_ENABLE: 1 = use enable (en pin active), 0 = no enable pin
       (Xilinx Register default: off) */
    parameter USE_ENABLE = 0,
    /* INIT_VAL: value loaded into q when rst is asserted */
    parameter INIT_VAL   = 0
)(
    input  clk,
    input  rst,
    input  en,
    input  [BITWIDTH-1:0] d,
    // Power-on value is given as a declaration initializer rather than an
    // 'initial' block: newer Verilator rejects a variable written by both an
    // 'initial' process and an always_ff (MULTIDRIVEN).
    output logic [BITWIDTH-1:0] q = BITWIDTH'(INIT_VAL)
);

generate
    if (USE_RST && USE_ENABLE) begin
        always_ff @(posedge clk)
            if (rst)     q <= BITWIDTH'(INIT_VAL);
            else if (en) q <= d;
    end else if (USE_RST && !USE_ENABLE) begin
        always_ff @(posedge clk)
            if (rst) q <= BITWIDTH'(INIT_VAL);
            else     q <= d;
    end else if (!USE_RST && USE_ENABLE) begin
        always_ff @(posedge clk)
            if (en) q <= d;
    end else begin
        always_ff @(posedge clk)
            q <= d;
    end
endgenerate

endmodule
