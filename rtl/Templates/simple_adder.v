// simle_adder.v
module simple_adder (
    input  wire rst,
    input  wire clk,
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg [8:0] sum = 0
);

always @(posedge clk)
begin
    if(rst == 1)
        sum <= 0;
    else
        sum <= a + b;
end

endmodule