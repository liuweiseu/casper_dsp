// square_transposer — transpose N x N blocks across N = 2^LOG2_N_LANES lanes
//
// Corresponds to casper_library's square_transposer (synchronous path),
// built as square_transposer_init.m draws it — delays and a barrel switcher,
// no RAM:
//
//   din[q] ─► delay q ─► barrel_switcher input (N - q) mod N
//   barrel_switcher output q ─► delay N-1-q ─► dout[q]
//   sel = a LOG2_N_LANES-bit down counter, cleared by sync (0, N-1, N-2, …)
//   sync ─► barrel_switcher (LOG2_N_LANES) ─► delay N-1 ─► sync_out
//
// Every path, data and sync, has latency LOG2_N_LANES + N - 1. When sync
// marks the start of a block, the N x N block of N lanes by N cycles comes
// out transposed (lane and time index swapped), which is how casper's
// fft_unscrambler regroups the outputs of parallel FFTs.
//
// ASYNC is declared for traceability; must be 0.

module square_transposer #(
    parameter int LOG2_N_LANES = 1,
    parameter int DATA_WIDTH   = 8,
    parameter int ASYNC        = 0
)(
    input  logic                  clk,
    input  logic                  sync,
    input  logic [DATA_WIDTH-1:0] din  [1 << LOG2_N_LANES],
    output logic                  sync_out,
    output logic [DATA_WIDTH-1:0] dout [1 << LOG2_N_LANES]
);

    localparam int N = 1 << LOG2_N_LANES;

    if (ASYNC != 0)       $fatal(1, "square_transposer: ASYNC is not implemented");
    if (LOG2_N_LANES < 1) $fatal(1, "square_transposer: LOG2_N_LANES must be >= 1");

    logic [LOG2_N_LANES-1:0] cnt;
    logic [DATA_WIDTH-1:0]   bs_in [N], bs_out [N];
    logic                    bs_sync;

    // casper Counter: Free Running, operation Down, rst = sync
    counter #(
        .COUNTER_TYPE(0), .NBITS(LOG2_N_LANES), .COUNT_DIR(1), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0)
    ) u_counter (.clk(clk), .rst(sync), .enable(1'b1), .dout(cnt));

    for (genvar q = 0; q < N; q++) begin : GEN_LANE
        // input q, delayed q, enters the barrel switcher at (N - q) mod N
        pipeline #(.BITWIDTH(DATA_WIDTH), .LATENCY(q)) u_df (
            .clk(clk), .din(din[q]), .dout(bs_in[(N - q) % N]));
        pipeline #(.BITWIDTH(DATA_WIDTH), .LATENCY(N - 1 - q)) u_db (
            .clk(clk), .din(bs_out[q]), .dout(dout[q]));
    end

    barrel_switcher #(.LOG2_N_LANES(LOG2_N_LANES), .DATA_WIDTH(DATA_WIDTH)) u_barrel_switcher (
        .clk(clk), .sel(cnt), .sync_in(sync), .din(bs_in), .dout(bs_out), .sync_out(bs_sync));

    pipeline #(.BITWIDTH(1), .LATENCY(N - 1)) u_dsync (
        .clk(clk), .din(bs_sync), .dout(sync_out));

endmodule
