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
// Memory contents power up to INIT_MEM (default 0): word w is
// INIT_MEM[w*DATA_WIDTH +: DATA_WIDTH]. dout_a / dout_b show INIT_A / INIT_B in the
// first cycle only; the output registers power up to 0, so a port whose first
// edge is disabled reads 0 until its first enabled read (as the built
// Simulink block does).
//
// Optional ports per port x = a / b, as the Xilinx Dual Port RAM's
// en_a/en_b and rst_a/rst_b options (xlDPBRAMXPM.sgm, latency 1):
//   enx  (EN_X = 1): enx = 0 disables port x: no read, no write, dout_x holds
//   rstx (RST_X = 1): dout_x <= INIT_X instead of the read, whether or not
//                     the port is enabled; a write of an enabled port still
//                     happens
// INIT_A / INIT_B are raw output-register words (power-on and reset values).
// The options and non-zero INIT_A / INIT_B / INIT_MEM are GENERIC only.
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
//   'Latency != 1 is not implemented. Memory powers up to INIT_MEM (raw words, default 0); the mapping sets initVector to zeros, so only INIT_MEM = 0 matches the standalone block. A non-zero INIT_MEM models a library RAM whose initVector Simulink quantizes to the dina type with Round / Saturate (xlDPBRAM.sgm xl_state(init, const_prec_a)); the instantiating module must apply that quantization.',
//   'INIT_A / INIT_B are raw output-register words; Simulink quantizes the real init_a / init_b to the dina / dinb type with Round / Saturate (xlDPBRAMXPM.sgm xtype(const_prec, inita)), so the exporter must convert them; for UFix_N_0 data the two are equal.',
// ]
//
// [params.ADDR_WIDTH]
// mask = 'depth'
// type = 'edit'
// expr = '2**ADDR_WIDTH'
// note = 'depth = 2^ADDR_WIDTH; non-power-of-two depths are not supported'
//
// [params.RST_A]
// mask = 'rst_a'
// type = 'checkbox'
// [params.RST_A.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.RST_B]
// mask = 'rst_b'
// type = 'checkbox'
// [params.RST_B.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.EN_A]
// mask = 'en_a'
// type = 'checkbox'
// [params.EN_A.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.EN_B]
// mask = 'en_b'
// type = 'checkbox'
// [params.EN_B.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.INIT_A]
// mask = 'init_a'
// type = 'edit'
// note = 'raw output-register word of port A (see deviations)'
//
// [params.INIT_B]
// mask = 'init_b'
// type = 'edit'
// note = 'raw output-register word of port B (see deviations)'
//
// [mask_set.initVector]
// template = 'zeros(1,{2**ADDR_WIDTH})'
//
// [mask_set.write_mode_A]
// value = 'Read Before Write'
//
// [mask_set.write_mode_B]
// value = 'Read Before Write'
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from dina (and dinb)'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
// INIT_MEM = 'raw power-on memory words, word w at bits [w*DATA_WIDTH +: DATA_WIDTH] (GENERIC only). For instances inside other blocks that model a library RAM initVector (e.g. xeng_descramble); the standalone mapping exports initVector as zeros, so only INIT_MEM = 0 has a Simulink reference'
//
// [mask_missing]
// distributed_mem = 'memory type is chosen by PLATFORM / synthesis'
// latency = 'read latency fixed at 1'
// optimize = 'implementation only'
//
// [ports]
// order = 'Simulink: addra, dina, wea, addrb, dinb, web, rsta, rstb, ena, enb -> A, B (port_label of a built block with all options on: both rsts before both ens); HDL: we_a, addr_a, din_a, dout_a, we_b, addr_b, din_b, dout_b, rsta, rstb, ena, enb'
// note = 'optional port names rsta, rstb, ena, enb from the block port_label (mask options rst_a, rst_b, en_a, en_b)'
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
// [ports.extra]
// @simulink-mapping end

module dual_port_ram #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter int    RST_A      = 0,      // 1 = rsta port enabled
    parameter int    RST_B      = 0,      // 1 = rstb port enabled
    parameter int    EN_A       = 0,      // 1 = ena port enabled
    parameter int    EN_B       = 0,      // 1 = enb port enabled
    parameter        INIT_A     = 0,      // raw output-register word
    parameter        INIT_B     = 0,      // raw output-register word
    // raw power-on memory contents, word w at [w*DATA_WIDTH +: DATA_WIDTH]
    parameter logic [(1<<ADDR_WIDTH)*DATA_WIDTH-1:0] INIT_MEM = 0,
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
    output logic [DATA_WIDTH-1:0] dout_b,
    input  logic                  rsta = 1'b0,
    input  logic                  rstb = 1'b0,
    input  logic                  ena  = 1'b1,
    input  logic                  enb  = 1'b1
);

    localparam logic [DATA_WIDTH-1:0] INIT_A_W = DATA_WIDTH'(INIT_A);
    localparam logic [DATA_WIDTH-1:0] INIT_B_W = DATA_WIDTH'(INIT_B);

    generate
        if (PLATFORM == "GENERIC") begin : GEN_GENERIC
            logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
            initial
                for (int w = 0; w < (1 << ADDR_WIDTH); w++)
                    mem[w] = INIT_MEM[w*DATA_WIDTH +: DATA_WIDTH];
            // power-on: dout_x shows INIT_X for the first cycle only; the
            // output registers start at 0 (built Simulink Dual Port RAM: a
            // disabled first edge leaves 0, not INIT_X)
            logic [DATA_WIDTH-1:0] dout_a_r = '0;
            logic [DATA_WIDTH-1:0] dout_b_r = '0;
            logic                  first    = 1'b1;
            logic                  a_en, b_en;
            assign a_en = (EN_A == 0) || ena;
            assign b_en = (EN_B == 0) || enb;
            // One process for both ports, so the memory has a single driver.
            always_ff @(posedge clk) begin
                first <= 1'b0;
                if (RST_A != 0 && rsta) dout_a_r <= INIT_A_W;
                else if (a_en)          dout_a_r <= mem[addr_a];
                if (RST_B != 0 && rstb) dout_b_r <= INIT_B_W;
                else if (b_en)          dout_b_r <= mem[addr_b];
                if (a_en && we_a) mem[addr_a] <= din_a;
                if (b_en && we_b) mem[addr_b] <= din_b;
            end
            assign dout_a = first ? INIT_A_W : dout_a_r;
            assign dout_b = first ? INIT_B_W : dout_b_r;
        end else if (RST_A != 0 || RST_B != 0 || EN_A != 0 || EN_B != 0
                     || INIT_A_W != '0 || INIT_B_W != '0 || (|INIT_MEM)) begin : GEN_BAD_OPTIONS
            $fatal(1, "dual_port_ram: RST_x / EN_x / INIT_x / INIT_MEM are implemented for PLATFORM \"GENERIC\" only");
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
