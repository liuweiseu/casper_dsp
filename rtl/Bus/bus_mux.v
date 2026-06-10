// Matches casper_library_bus/bus_mux (mlib_devel).
// n_inputs -> N_INPUTS, length(n_bits) -> N_CHANNELS, n_bits[k] -> CHANNEL_WIDTH (equal-width channels).
// sel width = N_CHANNELS * ceil(log2(N_INPUTS)); channel ch uses sel[ch*SEL_W +: SEL_W].
module bus_mux #(
    parameter int N_INPUTS      = 2,
    parameter int N_CHANNELS    = 2,
    parameter int CHANNEL_WIDTH = 18,
    parameter int MUX_LATENCY   = 0,
    parameter int MISC          = 0,
    parameter int MISC_WIDTH    = 1
)(
    input  clk,
    input  rst,
    input  [N_CHANNELS * $clog2(N_INPUTS > 1 ? N_INPUTS : 2)-1:0] sel,
    input  [N_CHANNELS*CHANNEL_WIDTH-1:0] d0,
    input  [N_CHANNELS*CHANNEL_WIDTH-1:0] d1,
    output [N_CHANNELS*CHANNEL_WIDTH-1:0] out,
    input  [MISC_WIDTH-1:0]               misci,
    output [MISC_WIDTH-1:0]               misco
);
    localparam int SEL_W  = $clog2(N_INPUTS > 1 ? N_INPUTS : 2);
    localparam int DATA_W = N_CHANNELS * CHANNEL_WIDTH;

    genvar s;

    reg [DATA_W-1:0] mux_out;

    always_comb begin
        mux_out = d0;
        for (int ch = 0; ch < N_CHANNELS; ch++) begin
            automatic int sel_val = sel[ch*SEL_W +: SEL_W];
            automatic int lo      = ch * CHANNEL_WIDTH;
            case (sel_val)
                0:       mux_out[lo +: CHANNEL_WIDTH] = d0[lo +: CHANNEL_WIDTH];
                1:       mux_out[lo +: CHANNEL_WIDTH] = d1[lo +: CHANNEL_WIDTH];
                default: mux_out[lo +: CHANNEL_WIDTH] = d0[lo +: CHANNEL_WIDTH];
            endcase
        end
    end

    generate
        if (MUX_LATENCY == 0) begin : gen_comb
            assign out = mux_out;
        end else begin : gen_pipe
            reg [DATA_W-1:0] pipe [0:MUX_LATENCY-1];

            always_ff @(posedge clk) begin
                if (rst) pipe[0] <= '0;
                else     pipe[0] <= mux_out;
            end

            for (s = 1; s < MUX_LATENCY; s++) begin : stages
                always_ff @(posedge clk) begin
                    if (rst) pipe[s] <= '0;
                    else     pipe[s] <= pipe[s-1];
                end
            end

            assign out = pipe[MUX_LATENCY-1];
        end
    endgenerate

    generate
        if (MISC == 0) begin : gen_no_misc
            assign misco = '0;
        end else if (MUX_LATENCY == 0) begin : gen_misc_comb
            assign misco = misci;
        end else begin : gen_misc_pipe
            reg [MISC_WIDTH-1:0] misc_pipe [0:MUX_LATENCY-1];

            always_ff @(posedge clk) begin
                if (rst) misc_pipe[0] <= '0;
                else     misc_pipe[0] <= misci;
            end

            for (s = 1; s < MUX_LATENCY; s++) begin : misc_stages
                always_ff @(posedge clk) begin
                    if (rst) misc_pipe[s] <= '0;
                    else     misc_pipe[s] <= misc_pipe[s-1];
                end
            end

            assign misco = misc_pipe[MUX_LATENCY-1];
        end
    endgenerate

endmodule
