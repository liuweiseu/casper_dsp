module bus_create #(
    parameter int NBITS   = 8,
    parameter int NINPUTS = 4
)(
    input  logic [NBITS-1:0] din [NINPUTS],
    output logic [(NBITS * NINPUTS)-1 : 0] bus_out
);

    always_comb begin
        for (int i = 0; i < NINPUTS; i++) begin
            bus_out[i * NBITS +: NBITS] = din[i];
        end
    end

endmodule