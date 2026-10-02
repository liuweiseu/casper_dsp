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
