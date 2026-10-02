// reorder — permute every MAP_LEN-sample frame by a fixed map (corner turn)
//
// Corresponds to casper_library's reorder (single buffered, double_buffer = 0,
// en always 1). Every frame of MAP_LEN samples on each of the N_STREAMS
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
// Timing (reorder_init.m): with REP = log2(N_STREAMS) and
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

module reorder #(
    parameter int    N_STREAMS           = 1,
    parameter int    DATA_WIDTH          = 8,
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
    input  logic [DATA_WIDTH-1:0] din  [N_STREAMS],
    output logic                  sync_out,
    output logic                  valid,
    output logic [DATA_WIDTH-1:0] dout [N_STREAMS]
);

    localparam int MAP_BITS = $clog2(MAP_LEN);
    localparam int REP      = $clog2(N_STREAMS);
    localparam int PRE      = (ORDER == 2) ? MAP_LATENCY + 1 : MAP_LATENCY + 2;
    localparam int DIN_DLY  = PRE + REP;
    localparam int OUT_DLY  = BRAM_LATENCY + FANOUT_LATENCY;
    localparam int W        = N_STREAMS * DATA_WIDTH;

    if (DOUBLE_BUFFER != 0)       $fatal(1, "reorder: DOUBLE_BUFFER is not implemented");
    if (SOFTWARE_CONTROLLED != 0) $fatal(1, "reorder: SOFTWARE_CONTROLLED is not implemented");
    if (MAP_LEN < 2 || (1 << MAP_BITS) != MAP_LEN) $fatal(1, "reorder: MAP_LEN must be a power of two >= 2");
    if (ORDER < 1)                $fatal(1, "reorder: ORDER must be >= 1");
    if (BRAM_LATENCY < 1)         $fatal(1, "reorder: BRAM_LATENCY must be >= 1");

    // ── streams side by side ─────────────────────────────────────────────────
    logic [W-1:0] din_w, din_d, dout_w;

    for (genvar s = 0; s < N_STREAMS; s++) begin : GEN_PACK
        assign din_w[s*DATA_WIDTH +: DATA_WIDTH] = din[s];
        assign dout[s] = dout_w[s*DATA_WIDTH +: DATA_WIDTH];
    end

    pipeline #(.BITWIDTH(W), .LATENCY(DIN_DLY)) u_din_dly (.clk(clk), .din(din_w), .dout(din_d));

    // ── sync / valid ─────────────────────────────────────────────────────────
    logic sync_pre, sync_frame;

    pipeline #(.BITWIDTH(1), .LATENCY(DIN_DLY)) u_sync_pre (.clk(clk), .din(sync), .dout(sync_pre));
    sync_delay #(.DELAY_LEN(MAP_LEN)) u_sync_delay (.clk(clk), .din(sync_pre), .dout(sync_frame));
    pipeline #(.BITWIDTH(1), .LATENCY(OUT_DLY)) u_sync_post (.clk(clk), .din(sync_frame), .dout(sync_out));
    pipeline #(.BITWIDTH(1), .LATENCY(DIN_DLY + OUT_DLY)) u_valid (.clk(clk), .din(1'b1), .dout(valid));

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
                pipeline #(.BITWIDTH(MAP_BITS), .LATENCY(1)) u_k_d (
                    .clk(clk), .din(cnt[MAP_BITS-1:0]), .dout(k_d));
                pipeline #(.BITWIDTH(1), .LATENCY(1)) u_sel_d (
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

                pipeline #(.BITWIDTH(MAP_BITS), .LATENCY(1)) u_k_d (.clk(clk), .din(k), .dout(k_d));
                pipeline #(.BITWIDTH(MAP_BITS), .LATENCY(1)) u_k_dd (.clk(clk), .din(k_d), .dout(k_dd));
                pipeline #(.BITWIDTH(1), .LATENCY(1)) u_first_d (.clk(clk), .din(first), .dout(first_d));

                // current_map: port A reads p_f[k], port B writes p_{f+1}[k] = map[p_f[k]]
                dual_port_ram #(.DATA_WIDTH(MAP_BITS), .ADDR_WIDTH(MAP_BITS), .PLATFORM(PLATFORM)) u_current_map (
                    .clk(clk),
                    .we_a(1'b0), .addr_a(k),    .din_a('0),    .dout_a(p_cur),
                    .we_b(1'b1), .addr_b(k_dd), .din_b(map_a), .dout_b());

                assign addr_early = first_d ? k_d : p_cur;

                rom #(.DATA_WIDTH(MAP_BITS), .ADDR_WIDTH(MAP_BITS), .INIT_FILE(MAP_INIT_FILE),
                      .PLATFORM(PLATFORM)) u_map (.clk(clk), .addr(addr_early), .dout(map_a));
            end

            pipeline #(.BITWIDTH(MAP_BITS), .LATENCY(DIN_DLY - 1)) u_addr_dly (
                .clk(clk), .din(addr_early), .dout(addr));

            single_port_ram #(.DATA_WIDTH(W), .ADDR_WIDTH(MAP_BITS), .PLATFORM(PLATFORM)) u_buf (
                .clk(clk), .we(1'b1), .addr(addr), .din(din_d), .dout(ram_q));

            pipeline #(.BITWIDTH(W), .LATENCY(OUT_DLY - 1)) u_out_dly (
                .clk(clk), .din(ram_q), .dout(dout_w));
        end
    endgenerate

endmodule
