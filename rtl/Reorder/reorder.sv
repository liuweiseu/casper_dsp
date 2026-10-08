// reorder — permute every MAP_LEN-sample frame by a fixed map (corner turn)
//
// Corresponds to casper_library's reorder (single buffered, double_buffer = 0,
// en always 1). Every frame of MAP_LEN samples on each of the N_INPUTS
// streams comes out permuted: output step k of a frame is input sample
// map[k] of the previous frame. All streams use the same addresses and are
// stored side by side in one read-before-write single_port_ram, as casper's
// per-stream RAMs are.
//
// The RAM is addressed, in the f-th frame after a sync, with map^f(k); a
// read-before-write access then returns the sample written there a frame
// earlier. map^f repeats with period ORDER (reorder_init.m's compute_order:
// lcm of the cycle lengths), which selects the address generator, as in
// casper:
//   ORDER = 1 : the identity map: a plain delay line (delay_bram)
//   ORDER = 2 : address = MSB of an (MAP_BITS+1)-bit frame counter ? map[k] : k
//   ORDER > 2 : address = p_f[k], an incrementally updated copy of map^f in a
//               dual_port_ram (p_0 = identity right after a sync, then
//               p_{f+1}[k] = map[p_f[k]]), as casper's current_map
//
// MAP_INIT_FILE holds the map (row k = map[k], one hex word per line) and
// ORDER / MAP_LEN come with it: generate all three with
// rtl/Reorder/scripts/gen_reorder_map.py. MAP_LEN must be a power of two.
//
// Timing (reorder_init.m): with REP = log2(N_INPUTS) and
//   PRE = MAP_LATENCY + 1        (ORDER = 2)
//   PRE = MAP_LATENCY + 2        (ORDER = 1 or > 2)
// the data reach the RAM PRE+REP cycles after din and leave it
// BRAM_LATENCY+FANOUT_LATENCY cycles later; sync_out is sync delayed by
// PRE+REP, then sync_delay(MAP_LEN), then BRAM_LATENCY+FANOUT_LATENCY. valid
// rises PRE+REP+BRAM_LATENCY+FANOUT_LATENCY cycles after reset (en = 1).
// The frame counter is cleared by sync. Syncs closer together than two
// cycles are not supported for ORDER > 2.
//
// Declared for traceability only: DOUBLE_BUFFER and SOFTWARE_CONTROLLED must
// be 0; BRAM_MAP (memory type of the map) is ignored.
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
// block = 'casper_library_reorder.slx/reorder'
// deviations = [
//   "The en input is not implemented: the HDL behaves as en = 1 (Simulink en gates the address Counter, every RAM write enable, valid via delay_we1, and the sync_delay_en enable via 'or' with the pre-sync; reorder_init.m:151-187, 257-259).",
//   'double_buffer = 1 and software_controlled = on (dbl_buffer RAMs, order forced to 2, optional shared_bram map; reorder_init.m:83-101, 453-499) are not implemented and $fatal (reorder.sv:99-100).',
//   "n_bits = 0 (the mask default) means 'inherit the data type' in Simulink and selects a plain xbsIndex Single Port RAM (reorder_init.m:288-292); the HDL needs an explicit N_BITS > 0. With n_bits > 0 Simulink instead uses bus_single_port_ram split into 64-bit words with zero init and reinterprets dout as unsigned n_bits (reorder_init.m:293-312); the HDL output bits are the same.",
//   "Power-on RAM contents differ for n_bits = 0: reuse_block sets only depth, so Simulink's Single Port RAM keeps the xbsIndex default initVector sin(pi*(0:15)/16) (quantized to the data type, zero-padded to 2^map_bits), which appears on dout during the first frame after power-on; the HDL single_port_ram powers up to 0 (single_port_ram.sv:9).",
//   'MAP_LEN must be a power of two >= 2 (reorder.sv:101); Simulink also requires a power of two but accepts length-1 maps.',
//   'The HDL computes REP = $clog2(N_INPUTS), so a non-power-of-two N_INPUTS is accepted with REP rounded up, whereas Simulink uses rep_latency = log2(n_inputs) (reorder_init.m:140) and fails on a non-integer Delay latency.',
//   'ORDER and MAP_INIT_FILE are taken on trust: Simulink derives order from map itself (compute_order), the HDL produces wrong output if ORDER does not match the map (use rtl/Reorder/scripts/gen_reorder_map.py).',
//   'The HDL map ROM, current_map RAM and data RAM all have a fixed 1-cycle latency and MAP_LATENCY / BRAM_LATENCY / FANOUT_LATENCY are made up with pipelines around them (reorder.sv:184-191); end-to-end latency matches reorder_init.m (pre_delay + rep_latency in, bram_latency + fanout_latency out), but the internal register split is not reproduced.',
//   "ORDER > 2: the HDL rebuilds casper's current_map loop (bus_dual_port_ram: port A written at daddr1 with addra/wea registered fan_latency = map_latency+2 and dina unregistered, port B read at daddr0, identity init; map_src Register reset by dsync and loaded by a falling-edge detect of the counter MSB; reorder_init.m:351-438) as a dual_port_ram with read on A, write on B, no init, and a 'first' flag set by sync / cleared at k = MAP_LEN-1 (reorder.sv:155-181); the equivalence is argued from the frame alignment but not verified bit-exactly, in particular for read/write collisions with very short maps.",
//   'ORDER > 2: syncs closer together than two cycles are not supported by the HDL (reorder.sv header); the Simulink map_src register resynchronises on any sync (dsync reset has priority over the edge-detect enable).',
//   'valid (power-on 0, rising PRE+REP+BRAM_LATENCY+FANOUT_LATENCY cycles after start) and sync_out (sync delayed PRE+REP, then sync_delay(MAP_LEN), then BRAM_LATENCY+FANOUT_LATENCY) match Simulink only under the en = 1 assumption.',
// ]
//
// [params.BRAM_MAP]
// mask = 'bram_map'
// type = 'checkbox'
// note = 'selects Block RAM vs Distributed memory (and Speed vs Area) for the map ROM / current_map only (reorder_init.m:103-111); no behavioural effect, ignored by the HDL'
// [params.BRAM_MAP.values]
// 0 = 'off'
// 1 = 'on'
//
// [params.SOFTWARE_CONTROLLED]
// mask = 'software_controlled'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = 'on forces double_buffer = 1 and a shared_bram map (reorder_init.m:83-101, 459-480); $fatal in the HDL'
// [params.SOFTWARE_CONTROLLED.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// MAP_LEN = "length(map): replaces the mask's vector map"
// ORDER = "order of map (reorder_init.m compute_order, or 2 when double_buffer = 1): replaces the mask's vector map; must be generated together with MAP_INIT_FILE"
// MAP_INIT_FILE = 'implementation: memory initialization file holding map'
// PLATFORM = 'implementation: memory / primitive vendor (GENERIC, XILINX, ALTERA)'
//
// [mask_missing]
// map = 'vector parameter: replaced by MAP_LEN, ORDER and MAP_INIT_FILE'
//
// [ports]
// order = 'Simulink inputs sync (1), en (2), din0.. (3..); outputs sync_out (1), valid (2), dout0.. (3..); the HDL has the same order without en'
// [ports.renamed]
// din = 'din0..din<N_INPUTS-1>'
// dout = 'dout0..dout<N_INPUTS-1>'
// [ports.missing]
// en = 'always present in Simulink (input port 2, reorder_init.m:151); the HDL assumes en = 1'
// [ports.extra]
// @simulink-mapping end

module reorder #(
    parameter int    N_INPUTS            = 1,
    parameter int    N_BITS              = 8,
    parameter int    MAP_LEN             = 8,
    parameter int    ORDER               = 4,
    parameter string MAP_INIT_FILE       = "",
    parameter int    MAP_LATENCY         = 2,
    parameter int    BRAM_LATENCY        = 1,
    parameter int    FANOUT_LATENCY      = 0,
    parameter string PLATFORM            = "GENERIC",
    // declared, not implemented (see header)
    parameter int    DOUBLE_BUFFER       = 0,
    parameter int    SOFTWARE_CONTROLLED = 0,
    parameter int    BRAM_MAP            = 1
)(
    input  logic                  clk,
    input  logic                  sync,
    input  logic [N_BITS-1:0] din  [N_INPUTS],
    output logic                  sync_out,
    output logic                  valid,
    output logic [N_BITS-1:0] dout [N_INPUTS]
);

    localparam int MAP_BITS = $clog2(MAP_LEN);
    localparam int REP      = $clog2(N_INPUTS);
    localparam int PRE      = (ORDER == 2) ? MAP_LATENCY + 1 : MAP_LATENCY + 2;
    localparam int DIN_DLY  = PRE + REP;
    localparam int OUT_DLY  = BRAM_LATENCY + FANOUT_LATENCY;
    localparam int W        = N_INPUTS * N_BITS;

    if (DOUBLE_BUFFER != 0)       $fatal(1, "reorder: DOUBLE_BUFFER is not implemented");
    if (SOFTWARE_CONTROLLED != 0) $fatal(1, "reorder: SOFTWARE_CONTROLLED is not implemented");
    if (MAP_LEN < 2 || (1 << MAP_BITS) != MAP_LEN) $fatal(1, "reorder: MAP_LEN must be a power of two >= 2");
    if (ORDER < 1)                $fatal(1, "reorder: ORDER must be >= 1");
    if (BRAM_LATENCY < 1)         $fatal(1, "reorder: BRAM_LATENCY must be >= 1");

    // ── streams side by side ─────────────────────────────────────────────────
    logic [W-1:0] din_w, din_d, dout_w;

    for (genvar s = 0; s < N_INPUTS; s++) begin : GEN_PACK
        assign din_w[s*N_BITS +: N_BITS] = din[s];
        assign dout[s] = dout_w[s*N_BITS +: N_BITS];
    end

    pipeline #(.BITWIDTH(W), .CSP_LATENCY(DIN_DLY)) u_din_dly (.clk(clk), .din(din_w), .dout(din_d));

    // ── sync / valid ─────────────────────────────────────────────────────────
    logic sync_pre, sync_frame;

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(DIN_DLY)) u_sync_pre (.clk(clk), .din(sync), .dout(sync_pre));
    sync_delay #(.DELAY_LEN(MAP_LEN)) u_sync_delay (.clk(clk), .din(sync_pre), .dout(sync_frame));
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(OUT_DLY)) u_sync_post (.clk(clk), .din(sync_frame), .dout(sync_out));
    pipeline #(.BITWIDTH(1), .CSP_LATENCY(DIN_DLY + OUT_DLY)) u_valid (.clk(clk), .din(1'b1), .dout(valid));

    generate
        if (ORDER == 1) begin : GEN_DELAY
            // identity map: casper's delay_bram_en_plus (DelayLen = MAP_LEN,
            // plus the BRAM latency)
            delay_bram #(.BITWIDTH(W), .DELAY_LEN(MAP_LEN + OUT_DLY), .PLATFORM(PLATFORM)) u_delay (
                .clk(clk), .din(din_d), .dout(dout_w));
        end else begin : GEN_RAM
            logic [MAP_BITS-1:0] addr_early;   // address for the sample entering now, +1 cycle
            logic [MAP_BITS-1:0] addr;         // aligned with din_d
            logic [W-1:0]        ram_q;

            if (ORDER == 2) begin : GEN_ORDER2
                // (MAP_BITS+1)-bit counter: low bits = step k, MSB = frame parity
                logic [MAP_BITS:0]   cnt;
                logic [MAP_BITS-1:0] k_d, map_k;
                logic                sel_d;

                counter #(
                    .COUNTER_TYPE(0), .NBITS(MAP_BITS + 1), .COUNT_DIR(0), .INIT_VAL(0),
                    .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0)
                ) u_counter (.clk(clk), .rst(sync), .enable(1'b1), .dout(cnt));

                rom #(.DATA_WIDTH(MAP_BITS), .ADDR_WIDTH(MAP_BITS), .INIT_FILE(MAP_INIT_FILE),
                      .PLATFORM(PLATFORM)) u_map (.clk(clk), .addr(cnt[MAP_BITS-1:0]), .dout(map_k));
                pipeline #(.BITWIDTH(MAP_BITS), .CSP_LATENCY(1)) u_k_d (
                    .clk(clk), .din(cnt[MAP_BITS-1:0]), .dout(k_d));
                pipeline #(.BITWIDTH(1), .CSP_LATENCY(1)) u_sel_d (
                    .clk(clk), .din(cnt[MAP_BITS]), .dout(sel_d));

                // casper Mux: d0 = counter (MSB 0), d1 = map(counter) (MSB 1)
                assign addr_early = sel_d ? map_k : k_d;
            end else begin : GEN_ORDER_N
                // step counter and "first frame after sync" flag (casper map_src)
                logic [MAP_BITS-1:0] k, k_d, k_dd, p_cur, map_a;
                logic                first, first_next, first_d;

                counter #(
                    .COUNTER_TYPE(0), .NBITS(MAP_BITS), .COUNT_DIR(0), .INIT_VAL(0),
                    .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0)
                ) u_counter (.clk(clk), .rst(sync), .enable(1'b1), .dout(k));

                assign first_next = sync ? 1'b1 : ((k == MAP_BITS'(MAP_LEN - 1)) ? 1'b0 : first);
                register #(.BITWIDTH(1), .USE_RST(0), .USE_ENABLE(0), .INIT_VAL(1)) u_first (
                    .clk(clk), .rst(1'b0), .en(1'b1), .d(first_next), .q(first));

                pipeline #(.BITWIDTH(MAP_BITS), .CSP_LATENCY(1)) u_k_d (.clk(clk), .din(k), .dout(k_d));
                pipeline #(.BITWIDTH(MAP_BITS), .CSP_LATENCY(1)) u_k_dd (.clk(clk), .din(k_d), .dout(k_dd));
                pipeline #(.BITWIDTH(1), .CSP_LATENCY(1)) u_first_d (.clk(clk), .din(first), .dout(first_d));

                // current_map: port A reads p_f[k], port B writes p_{f+1}[k] = map[p_f[k]]
                dual_port_ram #(.DATA_WIDTH(MAP_BITS), .ADDR_WIDTH(MAP_BITS), .PLATFORM(PLATFORM)) u_current_map (
                    .clk(clk),
                    .we_a(1'b0), .addr_a(k),    .din_a('0),    .dout_a(p_cur),
                    .we_b(1'b1), .addr_b(k_dd), .din_b(map_a), .dout_b());

                assign addr_early = first_d ? k_d : p_cur;

                rom #(.DATA_WIDTH(MAP_BITS), .ADDR_WIDTH(MAP_BITS), .INIT_FILE(MAP_INIT_FILE),
                      .PLATFORM(PLATFORM)) u_map (.clk(clk), .addr(addr_early), .dout(map_a));
            end

            pipeline #(.BITWIDTH(MAP_BITS), .CSP_LATENCY(DIN_DLY - 1)) u_addr_dly (
                .clk(clk), .din(addr_early), .dout(addr));

            single_port_ram #(.DATA_WIDTH(W), .ADDR_WIDTH(MAP_BITS), .PLATFORM(PLATFORM)) u_buf (
                .clk(clk), .we(1'b1), .addr(addr), .din(din_d), .dout(ram_q));

            pipeline #(.BITWIDTH(W), .CSP_LATENCY(OUT_DLY - 1)) u_out_dly (
                .clk(clk), .din(ram_q), .dout(dout_w));
        end
    endgenerate

endmodule
