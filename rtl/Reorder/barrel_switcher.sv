// barrel_switcher — pipelined lane rotation: dout[k] = din[(k + sel) mod N]
//
// Corresponds to casper_library's barrel_switcher (barrel_switcher_init.m),
// used inside square_transposer. N = 2^N_INPUTS lanes pass through
// N_INPUTS stages of 2:1 multiplexers (1 cycle each). In stage j
// (1 .. N_INPUTS) lane k either keeps its own value or takes lane
// (k + N/2^j) mod N of the previous stage, selected by bit N_INPUTS-j of
// sel (MSB first), delayed j-1 cycles so it meets the data it belongs to.
// Altogether the lanes are rotated by sel: dout[k](t + N_INPUTS) =
// din[(k + sel(t)) mod N](t). sync_out = sync_in delayed N_INPUTS cycles.
// Built from BasicModules/multiplexer and Delays/pipeline.
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
// block = 'casper_library_reorder.slx/barrel_switcher'
// deviations = [
//   "Simulink selects the stage-j select bit with an xbsIndex Slice (mode 'Upper Bit Location + Width', relative to 'MSB of Input', bit1 = -(j-1); barrel_switcher_init.m:97-98), i.e. the top n_inputs bits of whatever width sel has; the HDL sel port is exactly N_INPUTS bits, so a wider select signal must be pre-sliced to its top N_INPUTS bits (connecting it directly keeps the LSBs instead).",
//   'n_inputs = 0 is accepted by Simulink (it leaves an empty subsystem, barrel_switcher_init.m:57-62) but is a $fatal in the HDL (barrel_switcher.sv:54).',
//   'All lanes share one DATA_WIDTH in the HDL; in Simulink each In<i> keeps its own inherited type and the xbsIndex Mux blocks (latency 1, barrel_switcher_init.m:88-89) widen to a common full-precision type if lanes differ, so lanes must have identical fixed-point types to reproduce Simulink.',
//   'Power-on: the mux output registers and the sel/sync delays start at 0 in both models (xlMux/xlDelay init 0; multiplexer/pipeline power up to 0), so the first N_INPUTS outputs and sync_out are 0, as in Simulink.',
// ]
//
// [hdl_only]
// DATA_WIDTH = 'inherited width: Simulink takes it from the input signal'
//
// [mask_missing]
// async = 'async mode (en input / dvalid output) is not implemented; the HDL behaves as async = off'
//
// [ports]
// order = 'Simulink inputs sel, sync_in, In1..In<N> match the HDL; Simulink outputs are sync_out (port 1) then Out1..Out<N>, the HDL declares dout before sync_out'
// [ports.renamed]
// din = 'In1..In<2^N_INPUTS>'
// dout = 'Out1..Out<2^N_INPUTS>'
// [ports.missing]
// en = 'async=on only (not implemented)'
// dvalid = 'async=on only (not implemented)'
// [ports.extra]
// @simulink-mapping end

module barrel_switcher #(
    parameter int N_INPUTS     = 1,
    parameter int DATA_WIDTH   = 8
)(
    input  logic                    clk,
    input  logic [N_INPUTS-1:0] sel,
    input  logic                    sync_in,
    input  logic [DATA_WIDTH-1:0]   din  [1 << N_INPUTS],
    output logic [DATA_WIDTH-1:0]   dout [1 << N_INPUTS],
    output logic                    sync_out
);

    localparam int N = 1 << N_INPUTS;

    if (N_INPUTS < 1) $fatal(1, "barrel_switcher: N_INPUTS must be >= 1");

    // stage boundaries: lanes[0] = inputs, lanes[j] = output of stage j
    logic [DATA_WIDTH-1:0] lanes [N_INPUTS+1][N];

    for (genvar k = 0; k < N; k++) begin : GEN_IN
        assign lanes[0][k] = din[k];
        assign dout[k]     = lanes[N_INPUTS][k];
    end

    for (genvar j = 1; j <= N_INPUTS; j++) begin : GEN_STAGE
        logic [N_INPUTS-1:0] sel_d;
        pipeline #(.BITWIDTH(N_INPUTS), .CSP_LATENCY(j - 1)) u_sel_dly (
            .clk(clk), .din(sel), .dout(sel_d));

        for (genvar k = 0; k < N; k++) begin : GEN_LANE
            multiplexer #(.NBITS(DATA_WIDTH), .NINPUTS(2), .LATENCY(1)) u_mux (
                .clk (clk),
                .din ('{lanes[j-1][k], lanes[j-1][(k + (N >> j)) % N]}),
                .sel (sel_d[N_INPUTS - j]),
                .dout(lanes[j][k]));
        end
    end

    pipeline #(.BITWIDTH(1), .CSP_LATENCY(N_INPUTS)) u_sync_dly (
        .clk(clk), .din(sync_in), .dout(sync_out));

endmodule
