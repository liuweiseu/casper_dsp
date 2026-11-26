// dual_port_ram_altera — Altera/Intel implementation of
// rtl/Delays/dual_port_ram — STUB, NOT IMPLEMENTED
//
// Fixes the interface (same parameters minus PLATFORM, same ports and
// contract as dual_port_ram: two independent read/write ports on one clock,
// 1-cycle registered reads, READ_FIRST same-port read-during-write, contents
// and outputs power up to 0, cross-port same-address collisions undefined)
// so a real implementation is a drop-in replacement. Simulating or
// elaborating it with PLATFORM="ALTERA" stops with $fatal.
//
// TODO: port to Altera — instantiate altsyncram (or altera_syncram) with
//   operation_mode = "BIDIR_DUAL_PORT", address_reg_b = "CLOCK0" (common
//   clock), widthad_a/b = ADDR_WIDTH, width_a/b = DATA_WIDTH,
//   outdata_reg_a/b = "UNREGISTERED",
//   read_during_write_mode_port_a/b = "OLD_DATA".

module dual_port_ram_altera #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  we_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic [DATA_WIDTH-1:0] din_a,
    output logic [DATA_WIDTH-1:0] dout_a,
    input  logic                  we_b,
    input  logic [ADDR_WIDTH-1:0] addr_b,
    input  logic [DATA_WIDTH-1:0] din_b,
    output logic [DATA_WIDTH-1:0] dout_b
);

    assign dout_a = '0;
    assign dout_b = '0;

    initial $fatal(1, "dual_port_ram_altera is not implemented yet (TODO: altsyncram BIDIR_DUAL_PORT)");

endmodule
