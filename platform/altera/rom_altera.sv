// rom_altera — Altera/Intel implementation of rtl/Delays/rom
// — STUB, NOT IMPLEMENTED
//
// Fixes the interface (same parameters minus PLATFORM, same ports and
// contract as rom: 1-cycle registered read, contents from INIT_FILE,
// "" = all 0, output powers up to 0) so a real implementation is a drop-in
// replacement. Simulating or elaborating it with PLATFORM="ALTERA" stops
// with $fatal.
//
// TODO: port to Altera — instantiate altsyncram (or altera_syncram) with
//   operation_mode = "ROM", widthad_a = ADDR_WIDTH, width_a = DATA_WIDTH,
//   numwords_a = 2**ADDR_WIDTH, outdata_reg_a = "UNREGISTERED",
//   init_file = INIT_FILE. Quartus expects .mif or Intel-HEX init files, so
//   the plain one-word-per-line hex (.mem) format used by rom must be
//   converted (or loaded via $readmemh in an inferred-ROM fallback).

module rom_altera #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter string INIT_FILE  = ""
)(
    input  logic                  clk,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] dout
);

    assign dout = '0;

    initial $fatal(1, "rom_altera is not implemented yet (TODO: altsyncram ROM, init file %s)", INIT_FILE);

endmodule
