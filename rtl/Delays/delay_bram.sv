// delay_bram — long delay line in RAM
//
// dout = din delayed by DELAY_LEN clock cycles, stored in a single_port_ram
// instead of a register chain. Corresponds to casper_library's delay_bram.
// Vendor selection is delegated to single_port_ram through PLATFORM; this
// module has no platform-specific logic of its own.
//
//   counter (0 .. DELAY_LEN-2, wraps) ──► addr ┐
//   din ──────────────────────────────► din   ├─ single_port_ram (READ_FIRST) ──► dout
//                                   we = 1    ┘
//
// Every cycle the RAM writes din at the current address and, READ_FIRST,
// returns the word written there M = DELAY_LEN-1 cycles earlier; the RAM's
// 1-cycle output register adds the last cycle: total delay = M + 1.
// The address counter wraps at M, so any DELAY_LEN >= 2 works (M need not be
// a power of two; RAM depth = 2^clog2(M)).
//
// DELAY_LEN < 2 is not worth a RAM: it falls back to a pipeline of DELAY_LEN
// registers (0 = combinational pass-through).
// The RAM and the output power up to 0, so the first DELAY_LEN outputs are 0.

module delay_bram #(
    parameter int    BITWIDTH  = 8,
    parameter int    DELAY_LEN = 16,
    parameter string PLATFORM  = "GENERIC"
)(
    input  logic                clk,
    input  logic [BITWIDTH-1:0] din,
    output logic [BITWIDTH-1:0] dout
);

    generate
        if (DELAY_LEN < 2) begin : GEN_SHORT
            pipeline #(
                .BITWIDTH(BITWIDTH),
                .LATENCY (DELAY_LEN)
            ) u_pipeline (
                .clk (clk),
                .din (din),
                .dout(dout)
            );
        end else begin : GEN_RAM
            localparam int M          = DELAY_LEN - 1;
            localparam int ADDR_WIDTH = (M > 1) ? $clog2(M) : 1;

            logic [ADDR_WIDTH-1:0] addr;

            // COUNTER_TYPE=1 (count_limit), up: 0, 1, …, M-1, 0, …
            counter #(
                .COUNTER_TYPE   (1),
                .NBITS          (ADDR_WIDTH),
                .COUNT_TO_VAL   (M - 1),
                .COUNT_DIR      (0),
                .INIT_VAL       (0),
                .STEP           (1),
                .ENABLE_SYNC_RST(0),
                .ENABLE_ENABLE  (0)
            ) u_counter (
                .clk   (clk),
                .rst   (1'b0),
                .enable(1'b1),
                .dout  (addr)
            );

            single_port_ram #(
                .DATA_WIDTH(BITWIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .PLATFORM  (PLATFORM)
            ) u_ram (
                .clk (clk),
                .we  (1'b1),
                .addr(addr),
                .din (din),
                .dout(dout)
            );
        end
    endgenerate

endmodule
