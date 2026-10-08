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
//
// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, ports (renamed HDL -> Simulink, missing,
// extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/Dual Port RAM'
// deviations = [
//   "Write mode is fixed to READ_FIRST ('Read Before Write') on both ports, but the mask default for write_mode_A/B is 'Read After Write' (write-first: dout = din on a write); 'No Read On Write' (hold last read) is also not implemented.",
//   "Cross-port collisions: Simulink (xlDPBRAMXPM.sgm) outputs NaN on a port whose address the other port writes (AinvalidatesB/BinvalidatesA), stores NaN on a write-write collision and errors for Boolean data; the HDL GENERIC model returns the old word and lets port B's write win (dual_port_ram.sv:9-13).",
//   'Asymmetric ports are not supported: Sysgen allows port B to be form_factor times wider than A (xlDPBRAMXPM.sgm: form_factor), the HDL uses one DATA_WIDTH for both ports.',
//   'Depth must be a power of two (2^ADDR_WIDTH); Simulink errors on addresses >= depth, the HDL wraps them.',
//   'initVector, init_a/init_b, latency != 1, rst/en ports are not implemented; memory and outputs power up to 0 (Simulink power-on: initVector rounded/saturated to the dina type, outputs = init_a/init_b).',
// ]
//
// [params.ADDR_WIDTH]
// mask = 'depth'
// type = 'edit'
// expr = '2**ADDR_WIDTH'
// note = 'depth = 2^ADDR_WIDTH; non-power-of-two depths are not supported'
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from dina (and dinb)'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// initVector = 'memory always powers up to 0'
// distributed_mem = 'memory type is chosen by PLATFORM / synthesis'
// init_a = 'output register A powers up to 0; no reset value'
// init_b = 'output register B powers up to 0; no reset value'
// rst_a = 'output-register reset port not implemented'
// rst_b = 'output-register reset port not implemented'
// en_a = 'port enable not implemented'
// en_b = 'port enable not implemented'
// latency = 'read latency fixed at 1'
// write_mode_A = "fixed to 'Read Before Write' (mask default 'Read After Write')"
// write_mode_B = "fixed to 'Read Before Write' (mask default 'Read After Write')"
// optimize = 'implementation only'
//
// [ports]
// order = 'Simulink: addra, dina, wea, addrb, dinb, web -> A, B (icon port_label); HDL: we_a, addr_a, din_a, dout_a, we_b, addr_b, din_b, dout_b'
// note = 'optional port names rsta/rstb/ena/enb from xlDPBRAMXPM.sgm'
// [ports.renamed]
// we_a = 'wea'
// addr_a = 'addra'
// din_a = 'dina'
// dout_a = 'A'
// we_b = 'web'
// addr_b = 'addrb'
// din_b = 'dinb'
// dout_b = 'B'
// [ports.missing]
// rsta = 'rst_a option only (not implemented)'
// rstb = 'rst_b option only (not implemented)'
// ena = 'en_a option only (not implemented)'
// enb = 'en_b option only (not implemented)'
// [ports.extra]
// @simulink-mapping end

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
