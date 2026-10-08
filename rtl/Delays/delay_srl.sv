// delay_srl — fixed-length shift-register delay with optional reset and enable
//
// dout = din delayed by DELAY_LEN clock cycles (DELAY_LEN enabled cycles when
// USE_ENABLE = 1). Extends the BasicModules/delay pattern with a synchronous
// reset and a clock enable, and corresponds to casper_library's delay_srl.
// Built as a chain of BasicModules/register stages.
//
//   din ──► register ──► register ──► … ──► register ──► dout
//           (DELAY_LEN stages; each has the same rst / en)
//
// USE_ENABLE : 1 = all stages shift only while en = 1; 0 = en ignored
// USE_RST    : 1 = rst synchronously clears every stage (rst takes priority
//                  over en); 0 = rst ignored
// DELAY_LEN  : 0 = combinational pass-through (rst / en have no effect)
//
// All stages power up to 0. With USE_RST = 0 the chain has no reset, which
// lets synthesis map it to SRL shift-register primitives.
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
// block = 'casper_library_delays.slx/delay_srl'
// deviations = [
//   'HDL defaults are USE_ENABLE = 1 and USE_RST = 1, while the Simulink block has no reset and async defaults to off; set USE_RST = 0 and USE_ENABLE = 0 (or 1 for async = on) to reproduce Simulink.',
//   'The mask-stored default DelayLen = -1 leaves the Simulink block empty (delay_srl_init.m: DelayLen < 0 -> clean_blocks); the HDL does not check DELAY_LEN < 0.',
// ]
//
// [params.USE_ENABLE]
// mask = 'async'
// type = 'checkbox'
// note = "async = on adds the en input (delay_srl_init.m: Delay blocks with 'en' = async)"
// [params.USE_ENABLE.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// BITWIDTH = 'inherited width: Simulink takes it from the input signal'
// USE_RST = 'synchronous reset added by the HDL (rst port)'
//
// [mask_missing]
//
// [ports]
// order = 'Simulink: in, en (en only with async = on); HDL: rst, en, din'
// [ports.renamed]
// din = 'in'
// dout = 'out'
// [ports.missing]
// [ports.extra]
// rst = 'synchronous reset (USE_RST)'
// @simulink-mapping end

module delay_srl #(
    parameter int BITWIDTH   = 8,
    parameter int DELAY_LEN  = 4,
    parameter int USE_ENABLE = 1,
    parameter int USE_RST    = 1
)(
    input  logic                clk,
    input  logic                rst,
    input  logic                en,
    input  logic [BITWIDTH-1:0] din,
    output logic [BITWIDTH-1:0] dout
);

    generate
        if (DELAY_LEN == 0) begin : GEN_COMB
            assign dout = din;
        end else begin : GEN_CHAIN
            logic [BITWIDTH-1:0] stage [0:DELAY_LEN];
            assign stage[0] = din;
            for (genvar i = 0; i < DELAY_LEN; i++) begin : GEN_STAGE
                register #(
                    .BITWIDTH  (BITWIDTH),
                    .USE_RST   (USE_RST),
                    .USE_ENABLE(USE_ENABLE),
                    .INIT_VAL  (0)
                ) u_register (
                    .clk(clk),
                    .rst(rst),
                    .en (en),
                    .d  (stage[i]),
                    .q  (stage[i+1])
                );
            end
            assign dout = stage[DELAY_LEN];
        end
    endgenerate

endmodule
