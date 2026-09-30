// dual_port_ram_xilinx — Xilinx implementation of rtl/Delays/dual_port_ram
//
// Same parameters (minus PLATFORM) and ports as dual_port_ram, and the same
// contract: two independent read/write ports on one clock, 1-cycle registered
// reads, READ_FIRST same-port read-during-write, contents and outputs power
// up to 0, cross-port same-address collisions undefined. Implemented with the
// Xilinx Parameterized Macro xpm_memory_tdpram (UG974) in common-clock mode.
//
// Needs the XPM library at elaboration: Vivado adds it automatically; other
// simulators need <Vivado>/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv.

module dual_port_ram_xilinx #(
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

    xpm_memory_tdpram #(
        .ADDR_WIDTH_A           (ADDR_WIDTH),
        .ADDR_WIDTH_B           (ADDR_WIDTH),
        .AUTO_SLEEP_TIME        (0),
        .BYTE_WRITE_WIDTH_A     (DATA_WIDTH),
        .BYTE_WRITE_WIDTH_B     (DATA_WIDTH),
        .CASCADE_HEIGHT         (0),
        .CLOCKING_MODE          ("common_clock"),
        .ECC_MODE               ("no_ecc"),
        .MEMORY_INIT_FILE       ("none"),
        .MEMORY_INIT_PARAM      ("0"),
        .MEMORY_OPTIMIZATION    ("true"),
        .MEMORY_PRIMITIVE       ("auto"),
        .MEMORY_SIZE            (DATA_WIDTH * (1 << ADDR_WIDTH)),
        .MESSAGE_CONTROL        (0),
        .READ_DATA_WIDTH_A      (DATA_WIDTH),
        .READ_DATA_WIDTH_B      (DATA_WIDTH),
        .READ_LATENCY_A         (1),
        .READ_LATENCY_B         (1),
        .READ_RESET_VALUE_A     ("0"),
        .READ_RESET_VALUE_B     ("0"),
        .RST_MODE_A             ("SYNC"),
        .RST_MODE_B             ("SYNC"),
        .SIM_ASSERT_CHK         (0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT           (1),
        .WAKEUP_TIME            ("disable_sleep"),
        .WRITE_DATA_WIDTH_A     (DATA_WIDTH),
        .WRITE_DATA_WIDTH_B     (DATA_WIDTH),
        .WRITE_MODE_A           ("read_first"),
        .WRITE_MODE_B           ("read_first")
    ) u_xpm_memory_tdpram (
        .clka          (clk),
        .rsta          (1'b0),
        .ena           (1'b1),
        .regcea        (1'b1),
        .wea           (we_a),
        .addra         (addr_a),
        .dina          (din_a),
        .douta         (dout_a),
        .clkb          (clk),
        .rstb          (1'b0),
        .enb           (1'b1),
        .regceb        (1'b1),
        .web           (we_b),
        .addrb         (addr_b),
        .dinb          (din_b),
        .doutb         (dout_b),
        .sleep         (1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .injectsbiterrb(1'b0),
        .injectdbiterrb(1'b0),
        .sbiterra      (),
        .dbiterra      (),
        .sbiterrb      (),
        .dbiterrb      ()
    );

endmodule
