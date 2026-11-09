`timescale 1ns/1ps
`include "PATTERN.v"

module TESTBED;
    wire        clk1, clk2, clk3, rst_n, in_valid, out_valid;
    wire [31:0] in_data;
    wire [15:0] out_data;

    NTT_TOP I_NTT (
        .clk1(clk1), .clk2(clk2), .clk3(clk3), .rst_n(rst_n),
        .in_valid(in_valid), .in_data(in_data),
        .out_valid(out_valid), .out_data(out_data)
    );

    PATTERN I_PATTERN (
        .clk1(clk1), .clk2(clk2), .clk3(clk3), .rst_n(rst_n),
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
