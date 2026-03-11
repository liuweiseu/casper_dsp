module delay#(
    parameter LATENCY = 1,
    parameter BITWIDTH = 1
)(
    input clk,
    input [BITWIDTH - 1: 0] din,
    output [BITWIDTH - 1: 0] dout
);

// TODO: we may need rst signal and enable signal for this module

/* define the shift reg */
reg [BITWIDTH-1:0] shift_reg [0:LATENCY-1];

/* init the shift reg */
integer i;
initial 
    begin
        for(i=0; i<LATENCY; i=i+1)
            shift_reg[i] = {BITWIDTH{1'b0}};
    end

/* do shift */
always @(posedge clk) 
    begin
        shift_reg[0] <= din;
        for(i=1; i<LATENCY; i=i+1)
            shift_reg[i] <= shift_reg[i-1];
    end

assign dout = shift_reg[LATENCY-1];

endmodule