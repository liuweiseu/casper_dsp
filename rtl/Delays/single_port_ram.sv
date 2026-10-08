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
// block = 'xbsIndex_r4.slx/Single Port RAM'
// deviations = [
//   "Write mode is fixed to READ_FIRST ('Read Before Write'); the mask default is 'Read After Write' (xlSPRAM.sgm case 1: dout = data_in on a write) and 'No Read On Write' (dout holds last_value_read) is not implemented. casper delay_bram sets 'Read before write' explicitly, so it matches.",
//   'Read latency is fixed at 1; latency 0 (asynchronous read), latency > 1 and the rst/en ports (xlSPRAM.sgm: rst pushes init_reg, en = 0 freezes the output and blocks writes) are not implemented.',
//   'Memory and dout power up to 0; Simulink powers up to initVector (rounded/saturated to the data type) and init_reg (mask default initVector = sin(pi*(0:15)/16)).',
//   'Depth must be a power of two (2^ADDR_WIDTH); Simulink errors on addr > depth-1, the HDL wraps.',
// ]
//
// [params.ADDR_WIDTH]
// mask = 'depth'
// type = 'edit'
// expr = '2**ADDR_WIDTH'
// note = 'depth = 2^ADDR_WIDTH; non-power-of-two depths are not supported'
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from the data input'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// initVector = 'memory always powers up to 0'
// distributed_mem = 'memory type is chosen by PLATFORM / synthesis'
// write_mode = "fixed to 'Read Before Write' (mask default 'Read After Write')"
// rst = 'output-register reset port not implemented'
// init_reg = 'output register powers up to 0; no reset value'
// en = 'enable port not implemented'
// optimize_latency = 'implementation only'
// latency = 'read latency fixed at 1'
// optimize = 'implementation only'
//
// [ports]
// order = 'Simulink: addr, data, we -> dout (icon port_label); HDL: we, addr, din -> dout'
// [ports.renamed]
// din = 'data'
// [ports.missing]
// rst = 'rst option only (not implemented)'
// en = 'en option only (not implemented)'
// [ports.extra]
// @simulink-mapping end

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
