// Matches casper_library_flow_control/bus_expand (mlib_devel).
// WIDTHS[0..NOUT-1] defines each output's width; unused entries are ignored.
// TOTAL_IN is auto-computed as sum of first NOUT entries of WIDTHS.
// Equal-size mode: leave WIDTHS at default (all WIDTH); set only NOUT and WIDTH.
// Arbitrary-size mode: override WIDTHS with per-output widths; WIDTH must be >= max(WIDTHS[i]).
module bus_expand #(
    parameter int NOUT   = 4,
    parameter int WIDTH  = 8,
    parameter int WIDTHS[0:7] = '{WIDTH,WIDTH,WIDTH,WIDTH,WIDTH,WIDTH,WIDTH,WIDTH},
    parameter int TOTAL_IN    = WIDTHS[0]
                              + (NOUT > 1 ? WIDTHS[1] : 0)
                              + (NOUT > 2 ? WIDTHS[2] : 0)
                              + (NOUT > 3 ? WIDTHS[3] : 0)
                              + (NOUT > 4 ? WIDTHS[4] : 0)
                              + (NOUT > 5 ? WIDTHS[5] : 0)
                              + (NOUT > 6 ? WIDTHS[6] : 0)
                              + (NOUT > 7 ? WIDTHS[7] : 0)
)(
    input  logic [TOTAL_IN-1:0] bus_in,
    output logic [WIDTH-1:0]    bus_out [NOUT]
);

    function automatic int arb_offset(int idx);
        int s = 0;
        for (int i = 0; i < idx; i++) s += WIDTHS[i];
        return s;
    endfunction

    genvar i;
    generate
        for (i = 0; i < NOUT; i++) begin : gen_out
            localparam int OFF = arb_offset(i);
            localparam int W   = WIDTHS[i];
            logic [W-1:0] sliced;
            assign sliced     = bus_in[OFF +: W];
            assign bus_out[i] = WIDTH'(sliced);
        end
    endgenerate

endmodule
