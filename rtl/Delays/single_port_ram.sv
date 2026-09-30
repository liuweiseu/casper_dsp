// single_port_ram — single-port synchronous RAM with vendor dispatch
//
// Depth = 2^ADDR_WIDTH words of DATA_WIDTH bits, one read/write port.
// Every clock edge reads mem[addr] into the output register (1-cycle read
// latency) and, when we = 1, writes din to mem[addr].
//
// Read-during-write (we = 1): READ_FIRST — dout gets the OLD contents of
// mem[addr]; the new value is visible from the next access onward.
// Memory contents and dout power up to 0.
//
// PLATFORM selects the implementation (the port / parameter contract is the
// same on every platform):
//   "GENERIC" : behavioral description below (inferred RAM). Default; the
//               only path simulated by this repo's Verilator/cocotb flow.
//   "XILINX"  : platform/xilinx/single_port_ram_xilinx.sv (xpm_memory_spram)
//   "ALTERA"  : platform/altera/single_port_ram_altera.sv (stub, not
//               implemented yet)
// The XILINX / ALTERA sources are not in rtl/, so they must be added to the
// build (together with the vendor libraries) when those platforms are used.

module single_port_ram #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter string PLATFORM   = "GENERIC"
)(
    input  logic                  clk,
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout
);

    generate
        if (PLATFORM == "GENERIC") begin : GEN_GENERIC
            logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1] = '{default: '0};
            logic [DATA_WIDTH-1:0] dout_r = '0;
            always_ff @(posedge clk) begin
                dout_r <= mem[addr];
                if (we) mem[addr] <= din;
            end
            assign dout = dout_r;
        end else if (PLATFORM == "XILINX") begin : GEN_XILINX
            single_port_ram_xilinx #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) u_ram (.clk(clk), .we(we), .addr(addr), .din(din), .dout(dout));
        end else if (PLATFORM == "ALTERA") begin : GEN_ALTERA
            single_port_ram_altera #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) u_ram (.clk(clk), .we(we), .addr(addr), .din(din), .dout(dout));
        end else begin : GEN_BAD_PLATFORM
            $fatal(1, "single_port_ram: unsupported PLATFORM \"%s\" (GENERIC, XILINX, ALTERA)", PLATFORM);
        end
    endgenerate

endmodule
