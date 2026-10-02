// barrel_switcher — pipelined lane rotation: dout[k] = din[(k + sel) mod N]
//
// Corresponds to casper_library's barrel_switcher (barrel_switcher_init.m),
// used inside square_transposer. N = 2^LOG2_N_LANES lanes pass through
// LOG2_N_LANES stages of 2:1 multiplexers (1 cycle each). In stage j
// (1 .. LOG2_N_LANES) lane k either keeps its own value or takes lane
// (k + N/2^j) mod N of the previous stage, selected by bit LOG2_N_LANES-j of
// sel (MSB first), delayed j-1 cycles so it meets the data it belongs to.
// Altogether the lanes are rotated by sel: dout[k](t + LOG2_N_LANES) =
// din[(k + sel(t)) mod N](t). sync_out = sync_in delayed LOG2_N_LANES cycles.
// Built from BasicModules/multiplexer and Delays/pipeline.

module barrel_switcher #(
    parameter int LOG2_N_LANES = 1,
    parameter int DATA_WIDTH   = 8
)(
    input  logic                    clk,
    input  logic [LOG2_N_LANES-1:0] sel,
    input  logic                    sync_in,
    input  logic [DATA_WIDTH-1:0]   din  [1 << LOG2_N_LANES],
    output logic [DATA_WIDTH-1:0]   dout [1 << LOG2_N_LANES],
    output logic                    sync_out
);

    localparam int N = 1 << LOG2_N_LANES;

    if (LOG2_N_LANES < 1) $fatal(1, "barrel_switcher: LOG2_N_LANES must be >= 1");

    // stage boundaries: lanes[0] = inputs, lanes[j] = output of stage j
    logic [DATA_WIDTH-1:0] lanes [LOG2_N_LANES+1][N];

    for (genvar k = 0; k < N; k++) begin : GEN_IN
        assign lanes[0][k] = din[k];
        assign dout[k]     = lanes[LOG2_N_LANES][k];
    end

    for (genvar j = 1; j <= LOG2_N_LANES; j++) begin : GEN_STAGE
        logic [LOG2_N_LANES-1:0] sel_d;
        pipeline #(.BITWIDTH(LOG2_N_LANES), .LATENCY(j - 1)) u_sel_dly (
            .clk(clk), .din(sel), .dout(sel_d));

        for (genvar k = 0; k < N; k++) begin : GEN_LANE
            multiplexer #(.NBITS(DATA_WIDTH), .NINPUTS(2), .LATENCY(1)) u_mux (
                .clk (clk),
                .din ('{lanes[j-1][k], lanes[j-1][(k + (N >> j)) % N]}),
                .sel (sel_d[LOG2_N_LANES - j]),
                .dout(lanes[j][k]));
        end
    end

    pipeline #(.BITWIDTH(1), .LATENCY(LOG2_N_LANES)) u_sync_dly (
        .clk(clk), .din(sync_in), .dout(sync_out));

endmodule
