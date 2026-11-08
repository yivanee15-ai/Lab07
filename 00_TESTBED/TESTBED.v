`timescale 1ns/1ps
`ifndef CLK3_PERIOD
  `define CLK3_PERIOD 20.7
`endif
module TESTBED;
    parameter CLK1_P = 14.1;
    parameter CLK2_P = 10.1;
    parameter CLK3_P = `CLK3_PERIOD;

    reg clk1 = 0, clk2 = 0, clk3 = 0;
    always #(CLK1_P/2.0) clk1 = ~clk1;
    always #(CLK2_P/2.0) clk2 = ~clk2;
    always #(CLK3_P/2.0) clk3 = ~clk3;

    wire        rst_n, in_valid, out_valid;
    wire [31:0] in_data;
    wire [15:0] out_data;

    NTT_TOP I_NTT (
        .clk1(clk1), .clk2(clk2), .clk3(clk3), .rst_n(rst_n),
        .in_valid(in_valid), .in_data(in_data),
        .out_valid(out_valid), .out_data(out_data)
    );

    PATTERN I_PATTERN (
        .clk1(clk1), .clk3(clk3), .rst_n(rst_n),
        .in_valid(in_valid), .in_data(in_data),
        .out_valid(out_valid), .out_data(out_data)
    );

    initial begin
        if ($test$plusargs("wave")) begin
            $dumpfile("ntt.vcd");
            $dumpvars(0, TESTBED);
        end
    end
endmodule
