module bus_expand #(
    parameter int NOUT = 4,
    parameter int WIDTH = 8
)(
    input  logic [NOUT*WIDTH - 1:0] bus_in,
    output logic [WIDTH-1:0]        bus_out [NOUT]
);

// genvar i;
// generate
//     for (i = 0; i < NOUT; i++) begin : GEN_EXPAND
//         assign bus_out[i] = bus_in[i*WIDTH +: WIDTH];
//     end
// endgenerate

// TODO: We need to support divisions of arbitrary size
genvar i;
generate
    for (i = 0; i < NOUT; i++) begin : GEN_EXPAND
        slice #(
            .NBITS(NOUT*WIDTH),
            .START_BIT(i*WIDTH),
            .WIDTH(WIDTH)
        ) u_slice (
            .din(bus_in),
            .dout(bus_out[i])
        );
    end
endgenerate

endmodule