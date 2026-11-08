// 2-FF bus synchronizer (stand-in for the TA provided NDFF_BUS_syn)
module NDFF_BUS_syn #(parameter WIDTH = 7) (
    input  [WIDTH-1:0] D,
    input              clk,
    input              rst_n,
    output reg [WIDTH-1:0] Q
);
    reg [WIDTH-1:0] A1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A1 <= {WIDTH{1'b0}};
            Q  <= {WIDTH{1'b0}};
        end else begin
            A1 <= D;
            Q  <= A1;
        end
    end
endmodule
