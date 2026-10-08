// square_transposer — transpose N x N blocks across N = 2^N_INPUTS lanes
//
// Corresponds to casper_library's square_transposer (synchronous path),
// built as square_transposer_init.m draws it — delays and a barrel switcher,
// no RAM:
//
//   din[q] ─► delay q ─► barrel_switcher input (N - q) mod N
//   barrel_switcher output q ─► delay N-1-q ─► dout[q]
//   sel = a N_INPUTS-bit down counter, cleared by sync (0, N-1, N-2, …)
//   sync ─► barrel_switcher (N_INPUTS) ─► delay N-1 ─► sync_out
//
// Every path, data and sync, has latency N_INPUTS + N - 1. When sync
// marks the start of a block, the N x N block of N lanes by N cycles comes
// out transposed (lane and time index swapped), which is how casper's
// fft_unscrambler regroups the outputs of parallel FFTs.
//
// ASYNC is declared for traceability; must be 0.
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
// block = 'casper_library_reorder.slx/square_transposer'
// deviations = [
//   'n_inputs = 0 is accepted by Simulink (empty subsystem, square_transposer_init.m:54-59) but is a $fatal in the HDL (square_transposer.sv:141); Simulink errors only for n_inputs < 0.',
//   'The lane delays are casper delay_slr blocks in Simulink (square_transposer_init.m:85-86, 104-120) and plain register pipelines in the HDL; both power up to 0, so the first N_INPUTS + N - 1 outputs and sync_out are 0 in both, but SLR-crossing register placement is not reproduced.',
//   'All lanes share one DATA_WIDTH in the HDL; Simulink lets each in<q> carry its own inherited type into the barrel_switcher muxes (see barrel_switcher), so lanes must have identical types to match.',
//   'The select counter matches Simulink (xbsIndex Counter: Free Running, Down, n_inputs bits, Unsigned, rst = sync, start 0, square_transposer_init.m:81-83): sync forces 0 on the next cycle and the count then runs N-1, N-2, ...; with async = off Simulink has no counter enable, as in the HDL.',
// ]
//
// [params.ASYNC]
// mask = 'async'
// type = 'checkbox'
// hdl_unsupported = [1]
// note = "mask default is off (library mask), but square_transposer_init.m's defaults list uses 'on'; the HDL $fatals on ASYNC != 0"
// [params.ASYNC.values]
// 0 = 'off'
// 1 = 'on'
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
//
// [ports]
// note = 'Simulink lane ports are 0-based (in0/out0 = port 2, square_transposer_init.m:73-78), so din[q] = in<q>, dout[q] = out<q>'
// [ports.renamed]
// din = 'in0..in<2^N_INPUTS-1>'
// dout = 'out0..out<2^N_INPUTS-1>'
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module square_transposer #(
    parameter int N_INPUTS     = 1,
    parameter int DATA_WIDTH   = 8,
    parameter int ASYNC        = 0
)(
    input  logic                  clk,
    input  logic                  sync,
    input  logic [DATA_WIDTH-1:0] din  [1 << N_INPUTS],
    output logic                  sync_out,
    output logic [DATA_WIDTH-1:0] dout [1 << N_INPUTS]
);

    localparam int N = 1 << N_INPUTS;

    if (ASYNC != 0)       $fatal(1, "square_transposer: ASYNC is not implemented");
    if (N_INPUTS < 1) $fatal(1, "square_transposer: N_INPUTS must be >= 1");

    logic [N_INPUTS-1:0] cnt;
    logic [DATA_WIDTH-1:0]   bs_in [N], bs_out [N];
    logic                    bs_sync;

    // casper Counter: Free Running, operation Down, rst = sync
    counter #(
        .COUNTER_TYPE(0), .NBITS(N_INPUTS), .COUNT_DIR(1), .INIT_VAL(0),
        .STEP(1), .ENABLE_SYNC_RST(1), .ENABLE_ENABLE(0)
    ) u_counter (.clk(clk), .rst(sync), .enable(1'b1), .dout(cnt));

    for (genvar q = 0; q < N; q++) begin : GEN_LANE
        // input q, delayed q, enters the barrel switcher at (N - q) mod N
        pipeline #(.BITWIDTH(DATA_WIDTH), .CSP_LATENCY(q)) u_df (
            .clk(clk), .din(din[q]), .dout(bs_in[(N - q) % N]));
        pipeline #(.BITWIDTH(DATA_WIDTH), .CSP_LATENCY(N - 1 - q)) u_db (
            .clk(clk), .din(bs_out[q]), .dout(dout[q]));
    end

    barrel_switcher #(.N_INPUTS(N_INPUTS), .DATA_WIDTH(DATA_WIDTH)) u_barrel_switcher (
        .clk(clk), .sel(cnt), .sync_in(sync), .din(bs_in), .dout(bs_out), .sync_out(bs_sync));

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(N - 1)) u_dsync (
        .clk(clk), .din(bs_sync), .dout(sync_out));

endmodule
