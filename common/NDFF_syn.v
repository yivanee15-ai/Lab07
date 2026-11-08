// 2-FF synchronizer (stand-in for the TA provided NDFF_syn)
module NDFF_syn (
    input  D,
    input  clk,
    input  rst_n,
    output reg Q
);
    reg A1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A1 <= 1'b0;
            Q  <= 1'b0;
        end else begin
            A1 <= D;
            Q  <= A1;
        end
    end
endmodule
