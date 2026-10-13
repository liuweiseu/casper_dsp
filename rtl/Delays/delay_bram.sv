// delay_bram — long delay line in RAM
//
// dout = din delayed by DELAY_LEN clock cycles, stored in a single_port_ram
// instead of a register chain. Corresponds to casper_library's delay_bram.
// Vendor selection is delegated to single_port_ram through PLATFORM; this
// module has no platform-specific logic of its own.
//
//   counter (0 .. DELAY_LEN-2, wraps) ──► addr ┐
//   din ──────────────────────────────► din   ├─ single_port_ram (READ_FIRST) ──► dout
//                                   we = 1    ┘
//
// Every cycle the RAM writes din at the current address and, READ_FIRST,
// returns the word written there M = DELAY_LEN-1 cycles earlier; the RAM's
// 1-cycle output register adds the last cycle: total delay = M + 1.
// The address counter wraps at M, so any DELAY_LEN >= 2 works (M need not be
// a power of two; RAM depth = 2^clog2(M)).
//
// DELAY_LEN < 2 is not worth a RAM: it falls back to a pipeline of DELAY_LEN
// registers (0 = combinational pass-through).
// The RAM and the output power up to 0, so the first DELAY_LEN outputs are 0.
//
// ASYNC = 1 (casper async, port en; delay_bram_init.m:104-158): the counter,
// the RAM write and its output register only advance while en = 1, so the
// block is a delay of DELAY_LEN enabled samples and dout holds while en = 0
// (a full stall; there is no dvalid). The RAM en option is GENERIC only.
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
// block = 'casper_library_delays.slx/delay_bram'
// deviations = [
//   'Simulink (delay_bram_init.m) uses a counter limited to DelayLen-bram_latency-1 and a Read-before-write Single Port RAM with latency bram_latency; the HDL is the bram_latency = 1 case. dout is identical (din delayed by DelayLen, first DelayLen outputs 0) but the RAM output register count differs.',
//   'delay_bram_init.m errors for DelayLen <= bram_latency + 1 (DelayLen <= 3 with the default bram_latency 2) and deletes all lines for DelayLen = 0 (no din->dout path); the HDL accepts any DELAY_LEN and uses a register pipeline for DELAY_LEN < 2 (0 = wire).',
// ]
//
// [params.DELAY_LEN]
// mask = 'DelayLen'
// type = 'edit'
// note = 'same parameter; the mask name is camelCase'
//
// [[unsupported]]
// when = 'DELAY_LEN == 0'
// reason = 'mlib_devel bug 7 (docs/bugs.md): delay_bram_init.m:30-34 clears the block (clean_blocks) for DelayLen = 0, leaving it without din/dout ports, so it cannot be connected; the HDL is a wire'
//
// [[unsupported]]
// when = 'DELAY_LEN >= 1 && DELAY_LEN <= BRAM_LATENCY + 1'
// reason = 'mlib_devel bug 7 (docs/bugs.md): delay_bram_init.m:40-43 errors (delay value must be greater than BRAM Latency + 1) for DelayLen <= bram_latency + 1 (DelayLen 1 fails for any bram_latency); the HDL accepts any DELAY_LEN'
//
// [[unsupported]]
// when = 'ASYNC != 0 && BRAM_LATENCY == 1'
// reason = 'delay_bram_init.m:131-157: with async = on the loop that creates the bram_latency-1 output Delays and the dout port runs zero times for bram_latency = 1, so the block has no output port (confirmed in MATLAB R2021a: delay_bram has 0 output port(s), not 1)'
//
// [params.BRAM_LATENCY]
// mask = 'bram_latency'
// type = 'edit'
// note = 'only moves registers inside the block: dout is din delayed DELAY_LEN (enabled) samples either way, and the HDL ignores it; with async = on, bram_latency = 1 cannot be built (see unsupported)'
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// note = 'async = on: en stalls the counter, the RAM and the output stages, a delay of DelayLen enabled samples (delay_bram_init.m:104-158); no dvalid output. The HDL en port always exists'
// [params.ASYNC.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// BITWIDTH = 'inherited width: Simulink takes it from the input signal'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// use_dsp48 = 'counter resource choice only (Fabric vs DSP48)'
//
// [ports]
// order = 'Simulink: din, en (async only) -> dout (checked on a built block); HDL: the same order'
// [ports.renamed]
// [ports.missing]
// [ports.extra]
// @simulink-mapping end

module delay_bram #(
    parameter int    BITWIDTH  = 8,
    parameter int    DELAY_LEN = 16,
    parameter int    BRAM_LATENCY = 2,   // casper bram_latency (output timing only; see header)
    parameter int    ASYNC     = 0,      // casper async: 1 = en stalls the delay line
    parameter string PLATFORM  = "GENERIC"
)(
    input  logic                clk,
    input  logic [BITWIDTH-1:0] din,
    input  logic                en = 1'b1,
    output logic [BITWIDTH-1:0] dout
);

    generate
        if (DELAY_LEN < 2) begin : GEN_SHORT
            delay #(
                .LATENCY   (DELAY_LEN),
                .BITWIDTH  (BITWIDTH),
                .USE_ENABLE(int'(ASYNC != 0))
            ) u_pipeline (
                .clk (clk),
                .din (din),
                .en  (en),
                .dout(dout)
            );
        end else begin : GEN_RAM
            localparam int M          = DELAY_LEN - 1;
            localparam int ADDR_WIDTH = (M > 1) ? $clog2(M) : 1;

            logic [ADDR_WIDTH-1:0] addr;

            // COUNTER_TYPE=1 (count_limit), up: 0, 1, …, M-1, 0, …
            counter #(
                .COUNTER_TYPE   (1),
                .NBITS          (ADDR_WIDTH),
                .COUNT_TO_VAL   (M - 1),
                .COUNT_DIR      (0),
                .INIT_VAL       (0),
                .STEP           (1),
                .ENABLE_SYNC_RST(0),
                .ENABLE_ENABLE  (int'(ASYNC != 0))
            ) u_counter (
                .clk   (clk),
                .rst   (1'b0),
                .enable(en),
                .dout  (addr)
            );

            single_port_ram #(
                .DATA_WIDTH(BITWIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .EN        (int'(ASYNC != 0)),
                .PLATFORM  (PLATFORM)
            ) u_ram (
                .clk (clk),
                .we  (1'b1),
                .addr(addr),
                .din (din),
                .en  (en),
                .dout(dout)
            );
        end
    endgenerate

endmodule
