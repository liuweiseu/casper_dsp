// fifo — Xilinx System Generator FIFO block (xbsIndex_r4 "FIFO"; behaviour
// per the Sysgen 2021.1 block model data/sysgen/block_models/xlFIFOFWFT.sgm,
// whose output matched Simulink in both read modes on non-Versal parts once
// the differences listed in the mapping were applied)
//
// A synchronous FIFO of DEPTH words of DATA_WIDTH bits. All flags and counts
// are registered (they change on the clock edge after the write / read that
// causes them):
//   wr_en = we & en & ~rst_q & ~full        rd_en = re' & en & ~empty_int
// where rst_q is rst delayed RST_LATENCY - 1 cycles (rst itself when
// RST_LATENCY = 1) and re' is re in Standard mode and the FWFT prefetch
// request in First Word Fall Through mode.
//
// Standard mode (PERFORMANCE_OPTIONS = 0): dout shows the word read with re
// one cycle later (two with EMBEDDED_REGISTERS).
// empty / full refer to the stored words; dcount = stored words modulo DEPTH
// (it reads 0 when the FIFO is full); %full = stored words * 2^PERCENT_NBITS
// / DEPTH, all ones while full.
//
// First Word Fall Through (PERFORMANCE_OPTIONS = 1): the head word is
// prefetched into a two-stage output buffer, so dout already holds it while
// empty = 0 and re acknowledges it. The buffer adds two words: the FIFO holds
// DEPTH + 2 words, dcount has one more bit and %full = words * 2^PERCENT_NBITS
// / (2 * DEPTH). EMBEDDED_REGISTERS has no effect.
//
// ae / af are the programmable empty / full flags of xpm_fifo_sync: ae sets
// when a read-only cycle brings the stored count to ALMOST_EMPTY_THRESH and
// clears when a write-only cycle leaves it there; af sets when a write-only
// cycle reaches ALMOST_FULL_THRESH and clears when a read-only cycle leaves
// it (FWFT compares the RAM count with the thresholds minus 2).
//
// Reset (RST): rst_q clears the pointers, flags (empty / ae = 1, full / af =
// 0) and the output registers, not the memory contents. rd_rst_busy /
// wr_rst_busy follow the reset-busy logic of the XPM model (see the mapping).
// Ports whose option is off are ignored (inputs) or driven 0 (outputs); rst
// and en have default values, so instances that do not use them may leave
// them unconnected.
//
// ── HDL-Simulink Mapping ─────────────────────────────────────────────────────
// Differences between this HDL and its Simulink block (casper_library
// or Xilinx blockset). Machine-readable: the lines between the
// @simulink-mapping markers are TOML after removing the leading "// "
// (checked by tools/check_simulink_mapping.py). Fields: block,
// deviations, params (numeric HDL value -> mask option text, verbatim),
// hdl_only, mask_missing, unsupported, ports (renamed HDL -> Simulink,
// missing, extra).
// @simulink-mapping begin
// block = 'xbsIndex_r4.slx/FIFO'
// deviations = [
//   'Behaviour follows xlFIFOFWFT.sgm with four differences measured in Simulink (MATLAB R2021a, Sysgen 2021.1; SNAP and RFSoC4x2 behave the same): the model latency argument is rst_latency - 1; in Standard mode %full counts the stored words over depth (not the sgm dcount_std/2) and is not cleared during reset, and dcount is reported modulo depth (log2(depth) bits); the Standard-mode data latency does not depend on rst_latency (one cycle, two with embedded registers, whose second stage ignores en); in FWFT mode the output register is gated by en as in the sgm.',
//   'rd_rst_busy / wr_rst_busy: Simulink cannot simulate them on non-Versal parts (all CASPER platforms; the Gateway Out reports an inherited sample time, and libsysgen states the ports are available only for Versal devices), so they are unverified. The HDL drives both with the reset-busy logic of xlFIFOXPM.sgm: high from the cycle after power-on for 5 cycles and from the cycle after rst = 1 until 4 cycles after rst falls; they do not stall the FIFO.',
//   "mem_type = 'Built-in FIFO' is modelled as Block RAM: its Simulink model outputs NaN on empty / full for most cycles (measured), so there is no reference. 'Distributed RAM' and 'Shift Register' behave exactly as 'Block RAM' in Simulink (measured), including embedded_registers, which the mask dialog greys out for them (fifoenablement.m) but the model applies whatever the memory type (measured with Distributed RAM and Shift Register).",
//   'Simulink checks the thresholds only when their port is on: 3 <= threshold <= depth - 3 (Standard) and 5 <= threshold <= depth - 5 (FWFT); percent_nbits <= log2(depth); Shift Register does not support FWFT. The HDL stops with $fatal on the same conditions.',
//   'On UltraScale / UltraScale+ parts (e.g. RFSoC4x2) Simulink simulates the block only with rst = on and rst_latency >= 2 (otherwise every output has an inherited sample time); on 7-series parts (SNAP) rst may be off and rst_latency = 1. The HDL has no part parameter and accepts both.',
// ]
//
// [params.MEM_TYPE]
// mask = 'mem_type'
// type = 'popup'
// [params.MEM_TYPE.values]
// 0 = 'Block RAM'
// 1 = 'Distributed RAM'
// 2 = 'Shift Register'
// 3 = 'Built-in FIFO'
//
// [params.PERFORMANCE_OPTIONS]
// mask = 'performance_options'
// type = 'popup'
// [params.PERFORMANCE_OPTIONS.values]
// 0 = 'Standard_FIFO'
// 1 = 'First_Word_Fall_Through'
//
// [params.EMBEDDED_REGISTERS]
// mask = 'embedded_registers'
// type = 'checkbox'
// [params.EMBEDDED_REGISTERS.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.DEPTH]
// mask = 'depth'
// type = 'popup'
// [params.DEPTH.values]
// 16 = '16'
// 32 = '32'
// 64 = '64'
// 128 = '128'
// 256 = '256'
// 512 = '512'
// 1024 = '1K'
// 2048 = '2K'
// 4096 = '4K'
// 8192 = '8K'
// 16384 = '16K'
// 32768 = '32K'
// 65536 = '64K'
// 131072 = '128K'
// 262144 = '256K'
// 524288 = '512K'
// 1048576 = '1M'
// 2097152 = '2M'
// 4194304 = '4M'
//
// [params.PERCENT_NBITS]
// mask = 'percent_nbits'
// type = 'popup'
// [params.PERCENT_NBITS.values]
// 1 = '1'
// 2 = '2'
// 3 = '3'
// 4 = '4'
// 5 = '5'
// 6 = '6'
// 7 = '7'
// 8 = '8'
// 9 = '9'
// 10 = '10'
// 11 = '11'
// 12 = '12'
// 13 = '13'
// 14 = '14'
// 15 = '15'
// 16 = '16'
// 17 = '17'
// 18 = '18'
// 19 = '19'
// 20 = '20'
// 21 = '21'
// 22 = '22'
//
// [params.RST]
// mask = 'rst'
// type = 'checkbox'
// [params.RST.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.RST_LATENCY]
// mask = 'rst_latency'
// type = 'popup'
// [params.RST_LATENCY.values]
// 0 = '0'
// 1 = '1'
// 2 = '2'
// 3 = '3'
// 4 = '4'
// 5 = '5'
//
// [params.EN]
// mask = 'en'
// type = 'checkbox'
// [params.EN.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_DCOUNT]
// mask = 'use_dcount'
// type = 'checkbox'
// [params.USE_DCOUNT.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_PERCENT_FULL_PORT]
// mask = 'use_percent_full_port'
// type = 'checkbox'
// [params.USE_PERCENT_FULL_PORT.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_ALMOST_EMPTY]
// mask = 'use_almost_empty'
// type = 'checkbox'
// [params.USE_ALMOST_EMPTY.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.ALMOST_EMPTY_THRESH]
// mask = 'almost_empty_thresh'
// type = 'edit'
//
// [params.USE_ALMOST_FULL]
// mask = 'use_almost_full'
// type = 'checkbox'
// [params.USE_ALMOST_FULL.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.ALMOST_FULL_THRESH]
// mask = 'almost_full_thresh'
// type = 'edit'
//
// [params.USE_RD_RST_BUSY]
// mask = 'use_rd_rst_busy'
// type = 'checkbox'
// [params.USE_RD_RST_BUSY.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.USE_WR_RST_BUSY]
// mask = 'use_wr_rst_busy'
// type = 'checkbox'
// [params.USE_WR_RST_BUSY.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes din / dout from the input signal'
//
// [mask_missing]
// explicit_period = 'sample period has no HDL meaning'
// period = 'sample period has no HDL meaning'
//
// [[unsupported]]
// when = 'RST != 0 && RST_LATENCY == 0'
// reason = 'Simulink cannot simulate the block with rst_latency = 0 on any tested part (SNAP, RFSoC4x2): every output reports an inherited sample time'
//
// [[unsupported]]
// when = 'MEM_TYPE == 3'
// reason = "Built-in FIFO: the Simulink model outputs NaN on empty / full for most cycles (measured on SNAP), so there is no reference; the HDL models it as Block RAM"
//
// [[unsupported]]
// when = 'USE_RD_RST_BUSY != 0 || USE_WR_RST_BUSY != 0'
// reason = 'rd_rst_busy / wr_rst_busy exist only for Versal parts (libsysgen); on SNAP and RFSoC4x2 their Gateway Out reports an inherited sample time, so Simulink cannot simulate them'
//
// [ports]
// order = 'Simulink: din, we, re, rst, en -> dout, empty, %full, full, dcount, ae, af, rd_rst_busy, wr_rst_busy (only the enabled optional ports, in this order; icon port_label read in MATLAB). HDL: clk, din, we, re, rst, en -> the same outputs'
// note = 'percent_full is unsigned fixed point UFix_<percent_nbits>_<percent_nbits> in Simulink (a fraction); the HDL port carries its raw bits'
// [ports.renamed]
// percent_full = '%full'
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module fifo #(
    /* DATA_WIDTH: din / dout width (Simulink inherits it from din) */
    parameter int DATA_WIDTH = 8,
    /* MEM_TYPE: 0=Block RAM, 1=Distributed RAM, 2=Shift Register,
       3=Built-in FIFO (modelled as Block RAM) */
    parameter int MEM_TYPE = 0,
    /* PERFORMANCE_OPTIONS: 0=Standard FIFO, 1=First Word Fall Through */
    parameter int PERFORMANCE_OPTIONS = 0,
    /* EMBEDDED_REGISTERS: extra output register (Standard mode; the
       Simulink model adds it for every MEM_TYPE) */
    parameter int EMBEDDED_REGISTERS = 0,
    /* DEPTH: number of words, a power of two from 16 to 4M */
    parameter int DEPTH = 16,
    /* PERCENT_NBITS: width of percent_full (at most log2(DEPTH)) */
    parameter int PERCENT_NBITS = 1,
    /* RST: provide the rst port (1=enabled) */
    parameter int RST = 0,
    /* RST_LATENCY: cycles from rst to the reset taking effect (1..5) */
    parameter int RST_LATENCY = 1,
    /* EN: provide the en port (1=enabled) */
    parameter int EN = 0,
    /* USE_DCOUNT: provide the dcount port (1=enabled) */
    parameter int USE_DCOUNT = 0,
    /* USE_PERCENT_FULL_PORT: provide the percent_full port (1=enabled) */
    parameter int USE_PERCENT_FULL_PORT = 1,
    /* USE_ALMOST_EMPTY / ALMOST_EMPTY_THRESH: provide ae and its threshold */
    parameter int USE_ALMOST_EMPTY = 0,
    parameter int ALMOST_EMPTY_THRESH = 2,
    /* USE_ALMOST_FULL / ALMOST_FULL_THRESH: provide af and its threshold */
    parameter int USE_ALMOST_FULL = 0,
    parameter int ALMOST_FULL_THRESH = 14,
    /* USE_RD_RST_BUSY / USE_WR_RST_BUSY: provide the reset-busy ports */
    parameter int USE_RD_RST_BUSY = 0,
    parameter int USE_WR_RST_BUSY = 0,
    /* derived: log2(DEPTH) and the dcount width (one more bit in FWFT) */
    localparam int PW = $clog2(DEPTH),
    localparam int DCOUNT_WIDTH = (PERFORMANCE_OPTIONS != 0) ? PW + 1 : PW
)(
    input  logic                     clk,
    input  logic [DATA_WIDTH-1:0]    din,
    input  logic                     we,
    input  logic                     re,
    input  logic                     rst = 1'b0,
    input  logic                     en = 1'b1,
    output logic [DATA_WIDTH-1:0]    dout,
    output logic                     empty,
    output logic [PERCENT_NBITS-1:0] percent_full,
    output logic                     full,
    output logic [DCOUNT_WIDTH-1:0]  dcount,
    output logic                     ae,
    output logic                     af,
    output logic                     rd_rst_busy,
    output logic                     wr_rst_busy
);

localparam bit FWFT = (PERFORMANCE_OPTIONS != 0);
localparam bit EMB  = (EMBEDDED_REGISTERS != 0);
localparam int TH_MIN = FWFT ? 5 : 3;
localparam int TH_MAX = DEPTH - TH_MIN;
/* FWFT compares the RAM count with the thresholds minus the 2 buffer words */
localparam int AE_ADJ = FWFT ? ALMOST_EMPTY_THRESH - 2 : ALMOST_EMPTY_THRESH;
localparam int AF_ADJ = FWFT ? ALMOST_FULL_THRESH - 2 : ALMOST_FULL_THRESH;
/* the sgm reset delay: rst_latency - 1 cycles */
localparam int RST_DLY = (RST_LATENCY > 1) ? RST_LATENCY - 1 : 0;

/* check the parameters (the conditions Simulink rejects) */
initial
begin
    if (DEPTH < 16 || DEPTH > 4194304 || (1 << PW) != DEPTH)
        $fatal(1, "Error: DEPTH = %0d must be a power of two from 16 to 4M.", DEPTH);
    if (MEM_TYPE < 0 || MEM_TYPE > 3)
        $fatal(1, "Error: Invalid MEM_TYPE = %0d. (0=Block RAM, 1=Distributed RAM, 2=Shift Register, 3=Built-in FIFO)", MEM_TYPE);
    if (PERFORMANCE_OPTIONS != 0 && PERFORMANCE_OPTIONS != 1)
        $fatal(1, "Error: Invalid PERFORMANCE_OPTIONS = %0d. (0=Standard FIFO, 1=First Word Fall Through)", PERFORMANCE_OPTIONS);
    if (FWFT && MEM_TYPE == 2)
        $fatal(1, "Error: the Shift Register FIFO does not support First Word Fall Through.");
    if (PERCENT_NBITS < 1 || PERCENT_NBITS > 22 || PERCENT_NBITS > PW)
        $fatal(1, "Error: PERCENT_NBITS = %0d must be 1..22 and at most log2(DEPTH) = %0d.", PERCENT_NBITS, PW);
    if (RST_LATENCY < 0 || RST_LATENCY > 5)
        $fatal(1, "Error: RST_LATENCY = %0d must be 0..5.", RST_LATENCY);
    if (USE_ALMOST_EMPTY != 0 && (ALMOST_EMPTY_THRESH < TH_MIN || ALMOST_EMPTY_THRESH > TH_MAX))
        $fatal(1, "Error: ALMOST_EMPTY_THRESH = %0d must be between %0d and %0d.", ALMOST_EMPTY_THRESH, TH_MIN, TH_MAX);
    if (USE_ALMOST_FULL != 0 && (ALMOST_FULL_THRESH < TH_MIN || ALMOST_FULL_THRESH > TH_MAX))
        $fatal(1, "Error: ALMOST_FULL_THRESH = %0d must be between %0d and %0d.", ALMOST_FULL_THRESH, TH_MIN, TH_MAX);
end

/* optional inputs */
logic rst_i, en_i;
assign rst_i = (RST != 0) ? rst : 1'b0;
assign en_i  = (EN != 0) ? en : 1'b1;

/* rst delayed RST_LATENCY - 1 cycles */
logic rst_q;
generate
    if (RST_DLY == 0)
    begin : GEN_RST_NODELAY
        assign rst_q = rst_i;
    end
    else
    begin : GEN_RST_DELAY
        logic [RST_DLY-1:0] rst_sr = '0;
        always_ff @(posedge clk)
        begin
            rst_sr[0] <= rst_i;
            for (int k = 1; k < RST_DLY; k++)
                rst_sr[k] <= rst_sr[k-1];
        end
        assign rst_q = rst_sr[RST_DLY-1];
    end
endgenerate

/* FWFT output buffer states (xpm_fifo_sync encoding) */
localparam logic [1:0] INVALID = 2'd0;
localparam logic [1:0] STAGE2  = 2'd1;
localparam logic [1:0] STAGE1  = 2'd2;
localparam logic [1:0] BOTH    = 2'd3;

logic [DATA_WIDTH-1:0] mem [DEPTH] = '{default: '0};
logic [PW:0]           wr_ext = '0, rd_ext = '0;
logic [PW-1:0]         wr_p, rd_p;
logic                  empty_int = 1'b1;   // RAM empty
logic                  empty_fwft = 1'b1;  // FWFT output buffer empty
logic                  full_int = 1'b0;
logic                  prog_empty = 1'b1, prog_full = 1'b0;
logic                  wr_en_dly = 1'b0, rd_en_dly = 1'b0;
logic                  wr_only_dly = 1'b0, rd_only_dly = 1'b0;
logic [PW-1:0]         diff_pe = '0;
logic [1:0]            curr = INVALID, nxt;
logic [1:0]            extra = '0;
logic                  regce = 1'b0;
logic [DATA_WIDTH-1:0] dout_i = '0, dout_pipe = '0;

assign wr_p = wr_ext[PW-1:0];
assign rd_p = rd_ext[PW-1:0];

/* read / write enables */
logic rd_req, wr_en, rd_en;
assign rd_req = FWFT ? ((curr == BOTH) ? (~empty_int & re) : ~empty_int) : re;
assign wr_en  = we & en_i & ~rst_q & ~full_int;
assign rd_en  = rd_req & en_i & ~empty_int;

/* FWFT next state and output-register enable */
logic regout_en;
always_comb
begin
    nxt = INVALID;
    regout_en = 1'b0;
    if (FWFT)
    begin
        unique case (curr)
            INVALID: nxt = empty_int ? INVALID : STAGE1;
            STAGE1:  nxt = empty_int ? STAGE2 : BOTH;
            STAGE2:  nxt = (empty_int & re) ? INVALID : (~empty_int & re) ? STAGE1 :
                           ~empty_int ? BOTH : STAGE2;
            BOTH:    nxt = (empty_int & re) ? STAGE2 : BOTH;
        endcase
        regout_en = (curr == STAGE1) | ((curr == BOTH) & re);
    end
end

/* flag transitions */
logic going_empty, leaving_empty, going_full, leaving_full;
assign going_empty   = (wr_p == PW'(rd_p + 1'b1)) & ~wr_en & rd_en;
assign leaving_empty = (wr_p == rd_p) & wr_en;
assign going_full    = (rd_p == PW'(wr_p + 1'b1)) & wr_en & ~rd_en;
assign leaving_full  = (rd_p == wr_p) & rd_en;

/* programmable full: count as seen by the previous cycle's enables */
logic [PW-1:0] diff_pf;
assign diff_pf = rst_q ? '0 : (wr_p - rd_p + (wr_en_dly ? PW'(0) : PW'(1)));

logic wr_only, rd_only;
assign wr_only = wr_en & ~rd_en;
assign rd_only = rd_en & ~wr_en;

/* FWFT extra-word counter (words held in the output buffer) */
logic count_up, count_down;
assign count_up   = (nxt == STAGE1 && curr == INVALID) || (curr == STAGE1 && nxt == BOTH) ||
                    (curr == STAGE2 && nxt == BOTH);
assign count_down = (nxt == STAGE2 && curr == BOTH) || (curr == STAGE2 && nxt == INVALID);

always_ff @(posedge clk)
begin
    wr_en_dly <= wr_en;
    rd_en_dly <= rd_en;

    if (wr_en)
        mem[wr_p] <= din;

    if (rst_q)
    begin
        wr_ext      <= '0;
        rd_ext      <= '0;
        empty_int   <= 1'b1;
        empty_fwft  <= 1'b1;
        full_int    <= 1'b0;
        prog_full   <= 1'b0;
        prog_empty  <= 1'b1;
        wr_only_dly <= 1'b0;
        rd_only_dly <= 1'b0;
        diff_pe     <= '0;
        curr        <= INVALID;
        extra       <= '0;
        regce       <= 1'b0;
        dout_pipe   <= '0;
    end
    else
    begin
        if (wr_en) wr_ext <= wr_ext + 1'b1;
        if (rd_en) rd_ext <= rd_ext + 1'b1;
        empty_int  <= going_empty | (~leaving_empty & empty_int);
        empty_fwft <= ((curr == STAGE2) & re) | ((curr != STAGE1) & empty_fwft);
        if (going_full)
            full_int <= 1'b1;
        else if (leaving_full)
            full_int <= 1'b0;
        if (diff_pf == PW'(AF_ADJ) && wr_en_dly && !rd_en_dly)
            prog_full <= 1'b1;
        else if (diff_pf == PW'(AF_ADJ) && !wr_en_dly && rd_en_dly)
            prog_full <= 1'b0;
        if (diff_pe == PW'(AE_ADJ) && rd_only_dly)
            prog_empty <= 1'b1;
        else if (diff_pe == PW'(AE_ADJ) && wr_only_dly)
            prog_empty <= 1'b0;
        wr_only_dly <= wr_only;
        rd_only_dly <= rd_only;
        diff_pe     <= wr_p - rd_p - PW'(rd_only);
        if (FWFT)
            curr <= nxt;
        if (curr == INVALID && nxt == INVALID)
            extra <= '0;
        else if (count_up != count_down)
            extra <= count_up ? extra + 1'b1 : extra - 1'b1;
        regce <= rd_en;
        /* output register: FWFT loads on its buffer advance (gated by en);
           Standard mode with embedded registers one cycle after the read */
        if (FWFT ? (regout_en & en_i) : regce)
            dout_pipe <= dout_i;
    end

    /* RAM read register; Standard mode without embedded registers outputs
       it directly and clears it on reset */
    if (!FWFT && !EMB && rst_q)
        dout_i <= '0;
    else if (rd_en)
        dout_i <= mem[rd_p];
end

/* outputs */
logic [PW:0] words;
assign words = FWFT ? (PW+1)'(wr_ext - rd_ext + extra) : (wr_ext - rd_ext);

logic [PW:0] pf_raw;
assign pf_raw = FWFT ? (words >> (PW + 1 - PERCENT_NBITS)) : (words >> (PW - PERCENT_NBITS));

assign dout = (!FWFT && !EMB) ? dout_i : dout_pipe;
assign empty = FWFT ? empty_fwft : empty_int;
assign full = full_int;
assign dcount = (USE_DCOUNT != 0) ? DCOUNT_WIDTH'(words) : '0;
assign percent_full = (USE_PERCENT_FULL_PORT == 0) ? '0 :
                      (full_int || pf_raw >= (PW+1)'(1 << PERCENT_NBITS)) ? '1 :
                      PERCENT_NBITS'(pf_raw);
assign ae = (USE_ALMOST_EMPTY != 0) ? prog_empty : 1'b0;
assign af = (USE_ALMOST_FULL != 0) ? prog_full : 1'b0;

/* reset busy (xlFIFOXPM.sgm): a power-on pulse and rst load a 3-bit shift
   register; busy is its MSB OR'd with the MSB one cycle earlier */
logic [1:0] por = 2'b11;
logic [2:0] wr_rst = '0;
logic       busy_i = 1'b0, busy_dly = 1'b0;
logic       busy;
always_ff @(posedge clk)
begin
    por      <= {por[0], 1'b0};
    wr_rst   <= (por[1] | rst_i) ? 3'b111 : {wr_rst[1:0], 1'b0};
    busy_dly <= busy_i;
    busy_i   <= (por[1] | rst_i) ? 1'b1 : wr_rst[1];
end
assign busy = busy_i | busy_dly;
assign rd_rst_busy = (USE_RD_RST_BUSY != 0) ? busy : 1'b0;
assign wr_rst_busy = (USE_WR_RST_BUSY != 0) ? busy : 1'b0;

endmodule
