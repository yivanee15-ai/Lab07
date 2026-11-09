`timescale 1ns/1ps
module MON;
  real tf, tp; integer n=0; integer w=0; reg seen=0;
  always @(negedge TESTBED.in_valid) if ($realtime>100) tf=$realtime;
  always @(posedge TESTBED.I_NTT.in_data_valid_clk2) if (n<17) begin $display("dvalid %0d at +%0.1f (since in_valid fall)", n, $realtime-tf); n=n+1; end
  always @(posedge TESTBED.I_NTT.out_data_valid_clk2) if (w==0) begin $display("first winc at +%0.1f", $realtime-tf); w=1; end
  always @(posedge TESTBED.out_valid) if (!seen) begin $display("first out_valid at +%0.1f", $realtime-tf); seen=1; end
endmodule
