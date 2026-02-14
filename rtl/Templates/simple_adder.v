// simle_adder.v
module simple_adder (
    input  wire rst,
    input  wire clk,
    input  wire [3:0] a,
    input  wire [3:0] b,
    output reg [4:0] sum = 0
);

always @(posedge clk)
begin
    if(rst == 1)
        sum <= 0;
    else
        sum <= a + b;
end

endmodule