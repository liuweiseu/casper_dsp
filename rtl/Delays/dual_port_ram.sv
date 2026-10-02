// dual_port_ram — true dual-port synchronous RAM (common clock) with vendor
// dispatch
//
// Depth = 2^ADDR_WIDTH words of DATA_WIDTH bits. Ports A and B are fully
// independent read/write ports sharing one clock. On every clock edge each
// port reads mem[addr_x] into its output register (1-cycle read latency) and,
// when we_x = 1, writes din_x to mem[addr_x].
//
// Same-port read-during-write: READ_FIRST — dout_x gets the OLD contents.
// Cross-port collisions (both ports on the same address in the same cycle
// with at least one of them writing) are UNDEFINED by this module's contract,
// as they are for vendor block RAMs; callers must avoid them. (The GENERIC
// model happens to return the old data and let port B's write win, but other
// platforms need not match.)
// Memory contents and both outputs power up to 0.
//
// PLATFORM selects the implementation (same contract on every platform):
//   "GENERIC" : behavioral description below (inferred RAM). Default; the
//               only path simulated by this repo's Verilator/cocotb flow.
//   "XILINX"  : platform/xilinx/dual_port_ram_xilinx.sv (xpm_memory_tdpram)
//   "ALTERA"  : platform/altera/dual_port_ram_altera.sv (stub, not
//               implemented yet)

module dual_port_ram #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter string PLATFORM   = "GENERIC"
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

    generate
        if (PLATFORM == "GENERIC") begin : GEN_GENERIC
            logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1] = '{default: '0};
            logic [DATA_WIDTH-1:0] dout_a_r = '0;
            logic [DATA_WIDTH-1:0] dout_b_r = '0;
            // One process for both ports, so the memory has a single driver.
            always_ff @(posedge clk) begin
                dout_a_r <= mem[addr_a];
                dout_b_r <= mem[addr_b];
                if (we_a) mem[addr_a] <= din_a;
                if (we_b) mem[addr_b] <= din_b;
            end
            assign dout_a = dout_a_r;
            assign dout_b = dout_b_r;
        end else if (PLATFORM == "XILINX") begin : GEN_XILINX
            dual_port_ram_xilinx #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) u_ram (
                .clk(clk),
                .we_a(we_a), .addr_a(addr_a), .din_a(din_a), .dout_a(dout_a),
                .we_b(we_b), .addr_b(addr_b), .din_b(din_b), .dout_b(dout_b)
            );
        end else if (PLATFORM == "ALTERA") begin : GEN_ALTERA
            dual_port_ram_altera #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) u_ram (
                .clk(clk),
                .we_a(we_a), .addr_a(addr_a), .din_a(din_a), .dout_a(dout_a),
                .we_b(we_b), .addr_b(addr_b), .din_b(din_b), .dout_b(dout_b)
            );
        end else begin : GEN_BAD_PLATFORM
            $fatal(1, "dual_port_ram: unsupported PLATFORM \"%s\" (GENERIC, XILINX, ALTERA)", PLATFORM);
        end
    endgenerate

endmodule
