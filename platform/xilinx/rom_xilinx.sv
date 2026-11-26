// rom_xilinx — Xilinx implementation of rtl/Delays/rom
//
// Same parameters (minus PLATFORM) and ports as rom, and the same behavior:
// 1-cycle registered read, contents loaded from INIT_FILE ("" = all 0),
// output powers up to 0. Implemented with the Xilinx Parameterized Macro
// xpm_memory_sprom (UG974). XPM requires the init file to have the .mem
// extension; the hex one-word-per-line format rom documents is valid .mem.
//
// Needs the XPM library at elaboration: Vivado adds it automatically; other
// simulators need <Vivado>/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv.

module rom_xilinx #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter string INIT_FILE  = ""
)(
    input  logic                  clk,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] dout
);

    // XPM spells "no init file" as "none"
    localparam string XPM_INIT_FILE = (INIT_FILE == "") ? "none" : INIT_FILE;

    xpm_memory_sprom #(
        .ADDR_WIDTH_A       (ADDR_WIDTH),
        .AUTO_SLEEP_TIME    (0),
        .CASCADE_HEIGHT     (0),
        .ECC_MODE           ("no_ecc"),
        .MEMORY_INIT_FILE   (XPM_INIT_FILE),
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
        .WAKEUP_TIME        ("disable_sleep")
    ) u_xpm_memory_sprom (
        .clka          (clk),
        .rsta          (1'b0),
        .ena           (1'b1),
        .regcea        (1'b1),
        .addra         (addr),
        .douta         (dout),
        .sleep         (1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .sbiterra      (),
        .dbiterra      ()
    );

endmodule
