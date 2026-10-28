// single_port_ram — Xilinx System Generator Single Port RAM block
// (xbsIndex_r4 "Single Port RAM"), with vendor dispatch
//
// DEPTH words of DATA_WIDTH bits (DEPTH defaults to 2^ADDR_WIDTH), one
// read/write port. The behaviour follows the block as simulated in Simulink
// (MATLAB R2021a, System Generator 2021.1, SNAP / RFSoC4x2), which differs
// from the literal xlSPRAM.sgm text where noted.
//
// LATENCY >= 1: a pipeline of LATENCY registers. Stage 0 holds the word read
// on an enabled edge (en = 1, or no en port):
//   we = 0                      mem[addr]
//   we = 1, WRITE_MODE = 0      din        (Read After Write)
//   we = 1, WRITE_MODE = 1      mem[addr]  (Read Before Write: old contents)
//   we = 1, WRITE_MODE = 2      unchanged  (No Read On Write)
// and an enabled edge with we = 1 writes din to mem[addr]. Stages 1 ..
// LATENCY-1 shift on enabled edges; with Ultra RAM, or Block RAM with
// OPTIMIZE_LATENCY, they shift on every edge (only stage 0 sees en).
// dout is the last stage.
//
// rst (RST = 1) acts on the last stage only, whatever en is:
//   Block RAM: it loads INIT_REG, the power-on value of the last stage.
//   Ultra RAM: it clears the last stage (with LATENCY = 1 only on an enabled
//              edge) and dout reads 0 on the cycle after rst in any case;
//              INIT_REG is ignored (dout powers up to 0).
//   Distributed memory has no rst port: RST and INIT_REG are ignored.
// Enabled writes still happen during rst. The other stages power up to 0.
//
// LATENCY = 0 (Distributed memory, Read Before Write, no en port only):
// dout = mem[addr] combinationally; we = 1 writes din on the clock edge.
//
// Memory contents power up to the words of INIT_FILE ($readmemh, raw words;
// missing words are 0), or all 0 when INIT_FILE = "". Ultra RAM ignores
// INIT_FILE (Simulink ignores initVector). An address >= DEPTH, a Simulink
// simulation error, reads 0 and does not write.
//
// The module stops with $fatal on the parameter combinations Simulink
// rejects (see the parameter checks below).
//
// PLATFORM selects the implementation (the port / parameter contract is the
// same on every platform):
//   "GENERIC" : behavioral description below (inferred RAM). Default; the
//               only path simulated by this repo's Verilator/cocotb flow.
//   "XILINX"  : platform/xilinx/single_port_ram_xilinx.sv (xpm_memory_spram)
//   "ALTERA"  : platform/altera/single_port_ram_altera.sv (stub, not
//               implemented yet)
// XILINX / ALTERA implement only the default configuration (Block RAM, Read
// Before Write, LATENCY 1, DEPTH 2^ADDR_WIDTH, no rst / en / INIT_REG /
// INIT_FILE / OPTIMIZE_LATENCY). Their sources are not in rtl/, so they must
// be added to the build (together with the vendor libraries) when those
// platforms are used.
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
//   "Behaviour follows the block as simulated in Simulink (MATLAB R2021a, Sysgen 2021.1; SNAP, and RFSoC4x2 for Ultra RAM), which differs from the xlSPRAM.sgm text: rst acts on the last pipeline stage whatever en is and leaves the other stages running; the last stage alone powers up to init_reg; No Read On Write keeps stage 0 (so after a reset with latency 1 it repeats init_reg); Ultra RAM ignores init_reg and initVector, clears the last stage on rst (latency 1: only when enabled) and masks dout to 0 on the cycle after rst; with Ultra RAM, or Block RAM with optimize_latency, only the first stage is gated by en.",
//   'WRITE_MODE defaults to 1 (Read Before Write), not the mask default Read After Write, so existing instances keep their behaviour; INIT_FILE = "" gives all-zero contents, not the mask default sin(pi*(0:15)/16).',
//   'Contents: Simulink quantizes the real initVector to the data type with Round and Saturate (xlSPRAM.sgm: xfix(input_type, init_vals)) and truncates it to depth (a shorter vector leaves the other words 0); the HDL loads raw hex words from INIT_FILE, so the generator must apply that rounding / saturation and write at most DEPTH words.',
//   'INIT_REG is the raw output-register word; Simulink quantizes the real init_reg to the data type with Round / Saturate (xlSPRAM.sgm init_op_val), so the exporter must convert it; for UFix_N_0 data the two are equal.',
//   'Simulink errors on addr > depth-1 during simulation; the HDL reads 0 and ignores the write. ADDR_WIDTH (the addr width, inherited in Simulink) must hold DEPTH - 1.',
//   'Distributed memory: Simulink greys out rst / init_reg and builds no rst port even with rst checked; the HDL keeps the rst input (default 0) and ignores it. Ultra RAM exists only on UltraScale+ parts (e.g. RFSoC4x2); the HDL has no part parameter.',
// ]
//
// [params.DEPTH]
// mask = 'depth'
// type = 'edit'
// note = 'same parameter; HDL default 2^ADDR_WIDTH'
//
// [params.MEM_TYPE]
// mask = 'distributed_mem'
// type = 'popup'
// [params.MEM_TYPE.values]
// 0 = 'Distributed memory'
// 1 = 'Block RAM'
// 2 = 'Ultra RAM'
//
// [params.WRITE_MODE]
// mask = 'write_mode'
// type = 'popup'
// note = 'HDL default 1 (Read Before Write); the mask default is Read After Write'
// [params.WRITE_MODE.values]
// 0 = 'Read After Write'
// 1 = 'Read Before Write'
// 2 = 'No Read On Write'
//
// [params.LATENCY]
// mask = 'latency'
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
// [params.OPTIMIZE_LATENCY]
// mask = 'optimize_latency'
// type = 'checkbox'
// [params.OPTIMIZE_LATENCY.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.INIT_REG]
// mask = 'init_reg'
// type = 'edit'
// note = 'raw output-register word; init_reg in Simulink is a real value quantized to the data type (see deviations)'
//
// [mask_set.initVector]
// from_mem = 'INIT_FILE'
// [mask_set.initVector.else]
// template = 'zeros(1,{DEPTH})'
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from the data input'
// ADDR_WIDTH = 'inherited width: Simulink takes it from the addr input; it must hold DEPTH - 1'
// INIT_FILE = 'replaces initVector: $readmemh file of raw hex words (mask_set initVector reads it)'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// initVector = 'given as INIT_FILE (raw words) instead'
// optimize = 'implementation only (Area / Speed / Power; greyed out for every memory type)'
//
// [ports]
// order = 'Simulink: addr, data, we, rst, en -> dout (port_label of a built block with both options on); HDL: we, addr, din, rst, en -> dout'
// [ports.renamed]
// din = 'data'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module single_port_ram #(
    parameter int    DATA_WIDTH       = 8,
    parameter int    ADDR_WIDTH       = 4,
    parameter int    DEPTH            = 2 ** ADDR_WIDTH,  // words (mask depth)
    parameter int    MEM_TYPE         = 1,      // 0 Distributed memory, 1 Block RAM, 2 Ultra RAM
    parameter int    WRITE_MODE       = 1,      // 0 Read After Write, 1 Read Before Write, 2 No Read On Write
    parameter int    LATENCY          = 1,      // read latency (pipeline stages)
    parameter int    RST              = 0,      // 1 = rst port enabled
    parameter int    EN               = 0,      // 1 = en port enabled
    parameter int    OPTIMIZE_LATENCY = 0,      // 1 = mask optimize_latency on
    parameter        INIT_REG         = 0,      // raw output-register word
    parameter string INIT_FILE        = "",     // $readmemh image (raw words), "" = all 0
    parameter string PLATFORM         = "GENERIC"
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
    localparam bit URAM    = (MEM_TYPE == 2);
    localparam bit USE_RST = (RST != 0) && (MEM_TYPE != 0);   // Distributed memory: no rst port
    localparam bit USE_EN  = (EN != 0);
    // power-on / reset value of the last stage
    localparam logic [DATA_WIDTH-1:0] INIT_OUT = (USE_RST && !URAM) ? INIT_REG_W : '0;
    // stages 1 .. LATENCY-1 ignore en
    localparam bit FREE    = URAM || (MEM_TYPE == 1 && OPTIMIZE_LATENCY != 0);
    // the default configuration, the only one the vendor wrappers implement
    localparam bit DEFAULT_CFG = (DEPTH == 2 ** ADDR_WIDTH) && MEM_TYPE == 1 && WRITE_MODE == 1
                                 && LATENCY == 1 && RST == 0 && EN == 0 && OPTIMIZE_LATENCY == 0
                                 && INIT_REG_W == '0 && INIT_FILE == "";

    initial
    begin
        if (MEM_TYPE < 0 || MEM_TYPE > 2)
            $fatal(1, "single_port_ram: invalid MEM_TYPE = %0d (0 Distributed memory, 1 Block RAM, 2 Ultra RAM)", MEM_TYPE);
        if (WRITE_MODE < 0 || WRITE_MODE > 2)
            $fatal(1, "single_port_ram: invalid WRITE_MODE = %0d (0 Read After Write, 1 Read Before Write, 2 No Read On Write)", WRITE_MODE);
        if (DEPTH < 1 || DEPTH > 2 ** ADDR_WIDTH)
            $fatal(1, "single_port_ram: DEPTH = %0d must be 1 .. 2^ADDR_WIDTH = %0d", DEPTH, 2 ** ADDR_WIDTH);
        if (LATENCY < 0)
            $fatal(1, "single_port_ram: LATENCY = %0d must not be negative", LATENCY);
        // Simulink: "Latency in single port block RAM ... must be greater than 0"
        if (LATENCY == 0 && MEM_TYPE != 0)
            $fatal(1, "single_port_ram: LATENCY = 0 needs Distributed memory (MEM_TYPE = 0)");
        // Simulink: "For the specified latency of 0, Read before write mode is only supported ..."
        if (LATENCY == 0 && WRITE_MODE != 1)
            $fatal(1, "single_port_ram: LATENCY = 0 needs Read Before Write (WRITE_MODE = 1)");
        // Simulink: "Latency must be a positive integer if an enable port is specified"
        if (LATENCY == 0 && EN != 0)
            $fatal(1, "single_port_ram: LATENCY = 0 has no en port (EN = 0)");
        // Simulink: "No read on write mode is not supported for the single port distributed memory"
        if (MEM_TYPE == 0 && WRITE_MODE == 2)
            $fatal(1, "single_port_ram: Distributed memory does not support No Read On Write");
    end

    generate
        if (PLATFORM == "GENERIC") begin : GEN_GENERIC
            logic [DATA_WIDTH-1:0] mem [DEPTH];
            initial begin
                for (int i = 0; i < DEPTH; i++) mem[i] = '0;
                if (INIT_FILE != "" && !URAM) $readmemh(INIT_FILE, mem);
            end

            logic                  in_range;
            logic [DATA_WIDTH-1:0] rd;
            assign in_range = (int'(addr) < DEPTH);
            assign rd       = in_range ? mem[addr] : '0;

            if (LATENCY == 0) begin : GEN_ASYNC
                always_ff @(posedge clk)
                    if (we && in_range) mem[addr] <= din;
                assign dout = rd;
            end else begin : GEN_SYNC
                logic en_i, rst_i;
                assign en_i  = !USE_EN || en;
                assign rst_i = USE_RST && rst;

                // pipe[0] = word read, pipe[LATENCY-1] = output register
                logic [DATA_WIDTH-1:0] pipe [LATENCY] = '{(LATENCY - 1): INIT_OUT, default: '0};
                logic                  rst_q = 1'b0;   // Ultra RAM output mask
                logic [DATA_WIDTH-1:0] rd_word;
                assign rd_word = !we             ? rd   :
                                 WRITE_MODE == 0 ? din  :
                                 WRITE_MODE == 1 ? rd   : pipe[0];

                always_ff @(posedge clk) begin
                    if (en_i) begin
                        pipe[0] <= rd_word;
                        if (we && in_range) mem[addr] <= din;
                    end
                    for (int k = 1; k < LATENCY; k++)
                        if (en_i || FREE) pipe[k] <= pipe[k-1];
                    if (rst_i) begin
                        if (!URAM)
                            pipe[LATENCY-1] <= INIT_OUT;
                        else if (en_i || LATENCY > 1)
                            pipe[LATENCY-1] <= '0;
                    end
                    rst_q <= URAM && rst_i;
                end
                assign dout = rst_q ? '0 : pipe[LATENCY-1];
            end
        end else if (!DEFAULT_CFG) begin : GEN_BAD_OPTIONS
            $fatal(1, "single_port_ram: only the default configuration is implemented for PLATFORM \"%s\" (non-default options are GENERIC only)", PLATFORM);
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
