`timescale 1ns/1ps
module MONRT;
  real tp; integer n=0; integer hist[0:40]; integer i; real d;
  initial for (i=0;i<41;i=i+1) hist[i]=0;
  always @(posedge TESTBED.I_NTT.hs_dvalid) begin
    d = $realtime - tp;
    if (d < 400.0) begin i = d/10.1; if (i>40) i=40; hist[i] = hist[i]+1; end
    tp = $realtime;
  end
  final begin
    for (i=0;i<41;i=i+1) if (hist[i]) $display("RT %0d clk2 cycles (%0.1f..%0.1f ns): %0d", i, i*10.1, (i+1)*10.1, hist[i]);
  end
endmodule
