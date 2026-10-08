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
// block = 'xbsIndex_r4.slx/ROM'
// deviations = [
//   'Contents: Simulink quantizes the real initVector to {arith_type, n_bits, bin_pt} with Round and Saturate (xlSPROM.sgm: data_xfix_cell); the HDL loads raw hex words from INIT_FILE, so the generator must apply that rounding/saturation; INIT_FILE = "" gives all zeros, whereas the mask default is sin(pi*(0:15)/16).',
//   'Depth must be a power of two (2^ADDR_WIDTH); Simulink errors on addr > depth-1, the HDL wraps.',
//   'Read latency is fixed at 1 and dout powers up to 0; latency 0 (distributed, asynchronous read), latency > 1, init_reg != 0 and the rst/en ports are not implemented.',
// ]
//
// [params.ADDR_WIDTH]
// mask = 'depth'
// type = 'edit'
// expr = '2**ADDR_WIDTH'
// note = 'depth = 2^ADDR_WIDTH; non-power-of-two depths are not supported'
//
// [params.DATA_WIDTH]
// mask = 'n_bits'
// type = 'edit'
//
// [hdl_only]
// INIT_FILE = 'replaces initVector: $readmemh file of raw hex words'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// initVector = 'given as INIT_FILE (raw words) instead'
// distributed_mem = 'memory type is chosen by PLATFORM / synthesis'
// rst = 'output-register reset port not implemented'
// init_reg = 'output register powers up to 0; no reset value'
// en = 'enable port not implemented'
// latency = 'read latency fixed at 1'
// gui_display_data_type = 'HDL stores raw bit patterns (no Boolean / Floating-point)'
// arith_type = 'interpretation only; INIT_FILE holds the bit patterns'
// bin_pt = 'interpretation only; INIT_FILE holds the bit patterns'
// preci_type = 'floating point not implemented'
// exp_width = 'floating point not implemented'
// frac_width = 'floating point not implemented'
// optimize = 'implementation only'
// use_rpm = 'implementation only'
//
// [ports]
// note = 'addr / dout match the icon port_label'
// [ports.renamed]
// [ports.missing]
// rst = 'rst option only (not implemented)'
// en = 'en option only (not implemented)'
// [ports.extra]
// @simulink-mapping end

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
