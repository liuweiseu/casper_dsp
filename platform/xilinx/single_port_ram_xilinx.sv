// single_port_ram_xilinx — Xilinx implementation of rtl/Delays/single_port_ram
//
// Same parameters (minus PLATFORM) and ports as single_port_ram, and the same
// behavior: 1-cycle registered read, READ_FIRST read-during-write, contents
// and output power up to 0. Implemented with the Xilinx Parameterized Macro
// xpm_memory_spram (UG974), so Vivado chooses the RAM primitive
// (MEMORY_PRIMITIVE = "auto": block RAM or distributed RAM depending on size).
//
// Needs the XPM library at elaboration: Vivado adds it automatically; other
// simulators need <Vivado>/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv.

module single_port_ram_xilinx #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);

    xpm_memory_spram #(
        .ADDR_WIDTH_A       (ADDR_WIDTH),
        .AUTO_SLEEP_TIME    (0),
        .BYTE_WRITE_WIDTH_A (DATA_WIDTH),
        .CASCADE_HEIGHT     (0),
        .ECC_MODE           ("no_ecc"),
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  ("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE   ("auto"),
        .MEMORY_SIZE        (DATA_WIDTH * (1 << ADDR_WIDTH)),
        .MESSAGE_CONTROL    (0),
        .READ_DATA_WIDTH_A  (DATA_WIDTH),
        .READ_LATENCY_A     (1),
        .READ_RESET_VALUE_A ("0"),
        .RST_MODE_A         ("SYNC"),
        .SIM_ASSERT_CHK     (0),
        .USE_MEM_INIT       (1),
        .WAKEUP_TIME        ("disable_sleep"),
        .WRITE_DATA_WIDTH_A (DATA_WIDTH),
        .WRITE_MODE_A       ("read_first")
    ) u_xpm_memory_spram (
        .clka          (clk),
        .rsta          (1'b0),
        .ena           (1'b1),
        .regcea        (1'b1),
        .wea           (we),
        .addra         (addr),
        .dina          (din),
        .douta         (dout),
        .sleep         (1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .sbiterra      (),
        .dbiterra      ()
    );

endmodule
