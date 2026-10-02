// rom — synchronous read-only memory with vendor dispatch
//
// Depth = 2^ADDR_WIDTH words of DATA_WIDTH bits. Every clock edge reads
// mem[addr] into the output register (1-cycle read latency).
//
// INIT_FILE: memory image loaded at elaboration, one hexadecimal word per
// line ($readmemh format; use the .mem extension so the same file is also a
// valid Xilinx XPM MEMORY_INIT_FILE). A relative path is resolved against the
// simulator's / synthesis tool's working directory. "" = all words 0.
// dout powers up to 0.
//
// PLATFORM selects the implementation (same contract on every platform):
//   "GENERIC" : behavioral description below ($readmemh). Default; the only
//               path simulated by this repo's Verilator/cocotb flow.
//   "XILINX"  : platform/xilinx/rom_xilinx.sv (xpm_memory_sprom)
//   "ALTERA"  : platform/altera/rom_altera.sv (stub, not implemented yet)

module rom #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter string INIT_FILE  = "",
    parameter string PLATFORM   = "GENERIC"
)(
    input  logic                  clk,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] dout
);

    generate
        if (PLATFORM == "GENERIC") begin : GEN_GENERIC
            logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
            logic [DATA_WIDTH-1:0] dout_r = '0;
            initial begin
                for (int i = 0; i < (1 << ADDR_WIDTH); i++) mem[i] = '0;
                if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
            end
            always_ff @(posedge clk) dout_r <= mem[addr];
            assign dout = dout_r;
        end else if (PLATFORM == "XILINX") begin : GEN_XILINX
            rom_xilinx #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .INIT_FILE (INIT_FILE)
            ) u_rom (.clk(clk), .addr(addr), .dout(dout));
        end else if (PLATFORM == "ALTERA") begin : GEN_ALTERA
            rom_altera #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .INIT_FILE (INIT_FILE)
            ) u_rom (.clk(clk), .addr(addr), .dout(dout));
        end else begin : GEN_BAD_PLATFORM
            $fatal(1, "rom: unsupported PLATFORM \"%s\" (GENERIC, XILINX, ALTERA)", PLATFORM);
        end
    endgenerate

endmodule
