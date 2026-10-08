// sync_delay — delay a sync pulse by DELAY_LEN cycles with a counter
//
// Corresponds to casper_library's sync_delay (sync_delay_init.m): a
// loadable down counter replaces a DELAY_LEN-deep shift register.
//
//   din = 1         : load cnt <= DELAY_LEN  (a pulse restarts the delay)
//   else cnt != 0   : cnt <= cnt - 1
//   dout            = (cnt == 1)
//
// so a single pulse on din reappears on dout exactly DELAY_LEN cycles later.
// It differs from a plain delay line for pulses closer together than
// DELAY_LEN: each new pulse restarts the count, so only the last one comes
// out (casper sync pulses are one per frame, which is always >= DELAY_LEN
// apart). DELAY_LEN = 0 passes din straight through. cnt powers up to 0.
//
// The counter state is a BasicModules/register; casper's use_enable and
// prog_delay variants are not implemented.
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
// block = 'casper_library_delays.slx/sync_delay'
// deviations = []
//
// [hdl_only]
//
// [mask_missing]
//
// [ports]
// [ports.renamed]
// din = 'In'
// dout = 'Out'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module sync_delay #(
    parameter int DELAY_LEN = 16
)(
    input  logic clk,
    input  logic din,
    output logic dout
);

    generate
        if (DELAY_LEN == 0) begin : GEN_PASS
            assign dout = din;
        end else begin : GEN_COUNT
            localparam int NB = ($clog2(DELAY_LEN + 1) > 2) ? $clog2(DELAY_LEN + 1) : 2;

            logic [NB-1:0] cnt, cnt_next;

            always_comb begin
                if (din)             cnt_next = NB'(DELAY_LEN);
                else if (cnt != '0)  cnt_next = cnt - 1'b1;
                else                 cnt_next = '0;
            end

            register #(
                .BITWIDTH  (NB),
                .USE_RST   (0),
                .USE_ENABLE(0),
                .INIT_VAL  (0)
            ) u_cnt (
                .clk(clk),
                .rst(1'b0),
                .en (1'b1),
                .d  (cnt_next),
                .q  (cnt)
            );

            assign dout = (cnt == NB'(1));
        end
    endgenerate

endmodule
