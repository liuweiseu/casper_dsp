// rom — synchronous read-only memory with vendor dispatch
//
// Depth = 2^ADDR_WIDTH words of DATA_WIDTH bits. Every clock edge reads
// mem[addr] into the output register (1-cycle read latency).
//
// INIT_FILE: memory image loaded at elaboration, one hexadecimal word per
// line ($readmemh format; use the .mem extension so the same file is also a
// valid Xilinx XPM MEMORY_INIT_FILE). A relative path is resolved against the
// simulator's / synthesis tool's working directory. "" = all words 0.
// dout shows INIT_REG in the first cycle only: the output register itself
// powers up to 0, so if the first edge is disabled dout reads 0 until the
// first enabled read (as the built Simulink ROM does).
//
// Optional ports, as the Xilinx ROM's rst / en options (latency 1):
//   en  (EN = 1): en = 0 freezes dout
//   rst (RST = 1): dout <= INIT_REG instead of the read, whatever en is (the
//                  built block resets on en = 0 too, unlike the literal
//                  xlSPROM.sgm text)
// INIT_REG is the raw output-register word (power-on and reset value).
// The options and INIT_REG != 0 are GENERIC only.
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
//   'Read latency is fixed at 1; latency 0 (distributed, asynchronous read) and latency > 1 are not implemented.',
//   'INIT_REG is the raw output-register word; Simulink quantizes the real init_reg to {arith_type, n_bits, bin_pt} with Round / Saturate (xlSPROM.sgm init_op_val_xfix). With the mapped arith_type Unsigned and bin_pt 0, init_reg = INIT_REG.',
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
// [params.RST]
// mask = 'rst'
// type = 'checkbox'
// [params.RST.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.EN]
// mask = 'en'
// type = 'checkbox'
// [params.EN.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.INIT_REG]
// mask = 'init_reg'
// type = 'edit'
// note = 'raw output-register word; equals init_reg for the mapped Unsigned, bin_pt 0 data type'
//
// [mask_set.arith_type]
// value = 'Unsigned'
//
// [mask_set.bin_pt]
// value = 0
//
// [mask_set.initVector]
// from_mem = 'INIT_FILE'
// [mask_set.initVector.else]
// template = 'zeros(1,{2**ADDR_WIDTH})'
//
// [hdl_only]
// INIT_FILE = 'replaces initVector: $readmemh file of raw hex words (mask_set initVector reads it)'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// initVector = 'given as INIT_FILE (raw words) instead'
// distributed_mem = 'memory type is chosen by PLATFORM / synthesis'
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
// order = 'Simulink: addr, rst, en -> dout (port_label of a built block with both options on); HDL: addr, rst, en -> dout'
// note = 'addr / dout match the icon port_label'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module rom #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter string INIT_FILE  = "",
    parameter int    RST        = 0,      // 1 = rst port enabled
    parameter int    EN         = 0,      // 1 = en port enabled
    parameter        INIT_REG   = 0,      // raw output-register word
    parameter string PLATFORM   = "GENERIC"
)(
    input  logic                  clk,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic                  rst = 1'b0,
    input  logic                  en  = 1'b1,
    output logic [DATA_WIDTH-1:0] dout
);

    localparam logic [DATA_WIDTH-1:0] INIT_REG_W = DATA_WIDTH'(INIT_REG);

    generate
        if (PLATFORM == "GENERIC") begin : GEN_GENERIC
            logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
            // power-on: dout shows INIT_REG for the first cycle only; the
            // output register itself starts at 0 (built Simulink ROM: a
            // disabled first edge leaves 0, not INIT_REG)
            logic [DATA_WIDTH-1:0] dout_r = '0;
            logic                  first  = 1'b1;
            initial begin
                for (int i = 0; i < (1 << ADDR_WIDTH); i++) mem[i] = '0;
                if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
            end
            always_ff @(posedge clk) begin
                first <= 1'b0;
                if (RST != 0 && rst)    dout_r <= INIT_REG_W;   // rst wins over en
                else if (EN == 0 || en) dout_r <= mem[addr];
            end
            assign dout = first ? INIT_REG_W : dout_r;
        end else if (RST != 0 || EN != 0 || INIT_REG_W != '0) begin : GEN_BAD_OPTIONS
            $fatal(1, "rom: RST / EN / INIT_REG are implemented for PLATFORM \"GENERIC\" only");
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
