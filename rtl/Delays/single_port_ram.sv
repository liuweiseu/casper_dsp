// single_port_ram — single-port synchronous RAM with vendor dispatch
//
// Depth = 2^ADDR_WIDTH words of DATA_WIDTH bits, one read/write port.
// Every clock edge reads mem[addr] into the output register (1-cycle read
// latency) and, when we = 1, writes din to mem[addr].
//
// Read-during-write (we = 1): READ_FIRST — dout gets the OLD contents of
// mem[addr]; the new value is visible from the next access onward.
// Memory contents power up to 0, dout to INIT_REG.
//
// Optional ports, as the Xilinx Single Port RAM's rst / en options
// (xlSPRAM.sgm, latency 1):
//   en  (EN = 1): en = 0 freezes the edge: no read, no write, dout holds
//   rst (RST = 1): dout <= INIT_REG instead of the read, whatever en is (the
//                  built block resets on en = 0 too, unlike the literal
//                  xlSPRAM.sgm text); an enabled write still happens
// INIT_REG is the raw output-register word (power-on and reset value).
// The options and INIT_REG != 0 are GENERIC only.
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
//   'Read latency is fixed at 1; latency 0 (asynchronous read) and latency > 1 are not implemented.',
//   'Memory powers up to 0; the mapping sets initVector to zeros so Simulink does too (the mask default sin(pi*(0:15)/16) would give nonzero power-on contents). Other initVector contents are not supported.',
//   'INIT_REG is the raw output-register word; Simulink quantizes the real init_reg to the data type with Round / Saturate (xlSPRAM.sgm init_op_val), so the exporter must convert it; for UFix_N_0 data the two are equal.',
//   'Depth must be a power of two (2^ADDR_WIDTH); Simulink errors on addr > depth-1, the HDL wraps.',
// ]
//
// [params.ADDR_WIDTH]
// mask = 'depth'
// type = 'edit'
// expr = '2**ADDR_WIDTH'
// note = 'depth = 2^ADDR_WIDTH; non-power-of-two depths are not supported'
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
// note = 'raw output-register word; init_reg in Simulink is a real value quantized to the data type (see deviations)'
//
// [mask_set.initVector]
// template = 'zeros(1,{2**ADDR_WIDTH})'
//
// [mask_set.write_mode]
// value = 'Read Before Write'
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from the data input'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// distributed_mem = 'memory type is chosen by PLATFORM / synthesis'
// optimize_latency = 'implementation only'
// latency = 'read latency fixed at 1'
// optimize = 'implementation only'
//
// [ports]
// order = 'Simulink: addr, data, we, rst, en -> dout (port_label of a built block with both options on); HDL: we, addr, din, rst, en -> dout'
// [ports.renamed]
// din = 'data'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module single_port_ram #(
    parameter int    DATA_WIDTH = 8,
    parameter int    ADDR_WIDTH = 4,
    parameter int    RST        = 0,      // 1 = rst port enabled
    parameter int    EN         = 0,      // 1 = en port enabled
    parameter        INIT_REG   = 0,      // raw output-register word
    parameter string PLATFORM   = "GENERIC"
)(
    input  logic                  clk,
    input  logic                  we,
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] din,
    input  logic                  rst = 1'b0,
    input  logic                  en  = 1'b1,
    output logic [DATA_WIDTH-1:0] dout
);

    localparam logic [DATA_WIDTH-1:0] INIT_REG_W = DATA_WIDTH'(INIT_REG);

    generate
        if (PLATFORM == "GENERIC") begin : GEN_GENERIC
            logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1] = '{default: '0};
            logic [DATA_WIDTH-1:0] dout_r = INIT_REG_W;
            always_ff @(posedge clk) begin
                if (RST != 0 && rst)    dout_r <= INIT_REG_W;   // rst wins over en
                else if (EN == 0 || en) dout_r <= mem[addr];
                if ((EN == 0 || en) && we) mem[addr] <= din;
            end
            assign dout = dout_r;
        end else if (RST != 0 || EN != 0 || INIT_REG_W != '0) begin : GEN_BAD_OPTIONS
            $fatal(1, "single_port_ram: RST / EN / INIT_REG are implemented for PLATFORM \"GENERIC\" only");
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
