// single_port_ram_altera — Altera/Intel implementation of
// rtl/Delays/single_port_ram — STUB, NOT IMPLEMENTED
//
// Fixes the interface (same parameters minus PLATFORM, same ports and
// contract as single_port_ram: 1-cycle registered read, READ_FIRST
// read-during-write, contents and output power up to 0) so a real
// implementation is a drop-in replacement. Simulating or elaborating it
// with PLATFORM="ALTERA" stops with $fatal.
//
// TODO: port to Altera — instantiate altsyncram (or altera_syncram) with
//   operation_mode = "SINGLE_PORT", widthad_a = ADDR_WIDTH,
//   width_a = DATA_WIDTH, numwords_a = 2**ADDR_WIDTH,
//   outdata_reg_a = "UNREGISTERED" (the RAM input register gives the 1-cycle
//   read latency), read_during_write_mode_port_a = "OLD_DATA".

module single_port_ram_altera #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);

    assign dout = '0;

    initial $fatal(1, "single_port_ram_altera is not implemented yet (TODO: altsyncram SINGLE_PORT)");

endmodule
