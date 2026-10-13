// delay — Xilinx System Generator Delay block (xbsIndex_r4 "Delay")
//
// A LATENCY-stage shift register; LATENCY = 0 is a wire (rst and en are
// then ignored, as in the block model). Per clock edge:
//   rst (USE_RST)               every stage <= 0, including stage 0; nothing
//                               is shifted in, whatever en is
//   else en (USE_ENABLE; else on)  shift: stage 0 <= din, stage k <= stage k-1
// Power-on value 0. This follows the built Simulink block (MATLAB R2021a,
// delay sets 2 and 4), not the literal xlDelay.sgm text, which clears and
// then still pushes din when en = 1.
//
// Mask mapping: latency -> LATENCY, rst -> USE_RST, en -> USE_ENABLE
// (reg_retiming only selects the HDL style). Ports whose option is off are
// ignored; rst and en have default values, so instances that do not use
// them may leave them unconnected.
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
// block = 'xbsIndex_r4.slx/Delay'
// deviations = []
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
// reg_retiming = 'HDL style only (behavioural vs SRL), no behavioural effect'
//
// [ports]
// order = 'Simulink: d, rst, en (port_label of a built block with both options on, read by plugins-demo2; confirmed with delay set 2); HDL: din, rst, en. The xlDelay.sgm signature order delay(d, en, rst) is not the port order'
// note = 'ports map by name: din -> d, dout -> q'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module delay#(
    parameter LATENCY = 1,
    parameter BITWIDTH = 1,
    /* USE_RST: 1 = provide the synchronous reset port rst */
    parameter USE_RST = 0,
    /* USE_ENABLE: 1 = provide the enable port en */
    parameter USE_ENABLE = 0
)(
    input clk,
    input [BITWIDTH - 1: 0] din,
    input rst = 1'b0,
    input en = 1'b1,
    output [BITWIDTH - 1: 0] dout
);

generate
    if (LATENCY <= 0) begin : GEN_WIRE
        assign dout = din;
    end else begin : GEN_REG
        /* define the shift reg */
        reg [BITWIDTH-1:0] shift_reg [0:LATENCY-1];

        wire do_rst   = (USE_RST != 0) && rst;
        wire do_shift = (USE_ENABLE == 0) || en;

        /* init the shift reg */
        integer i;
        initial
            begin
                for(i=0; i<LATENCY; i=i+1)
                    shift_reg[i] = {BITWIDTH{1'b0}};
            end

        /* do shift */
        always @(posedge clk)
            begin
                if (do_rst)
                    begin
                        for(i=0; i<LATENCY; i=i+1)
                            shift_reg[i] <= {BITWIDTH{1'b0}};
                    end
                else if (do_shift)
                    begin
                        shift_reg[0] <= din;
                        for(i=1; i<LATENCY; i=i+1)
                            shift_reg[i] <= shift_reg[i-1];
                    end
            end

        assign dout = shift_reg[LATENCY-1];
    end
endgenerate

endmodule
