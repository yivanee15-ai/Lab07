`timescale 1ns/1ps
// din must stay constant between the request being raised and the acknowledge arriving
// (sampled in the middle of every clk1 cycle, so zero-delay glitches of the combinational mux are ignored)
module MONSTAB;
  wire [31:0] din = TESTBED.I_NTT.data_clk1;
  wire sreq = TESTBED.I_NTT.u_Handshake_syn.sreq;
  wire sack = TESTBED.I_NTT.u_Handshake_syn.sack;
  reg [31:0] ref_v; reg busy = 0; integer viol = 0, n = 0;
  always @(negedge TESTBED.clk1) begin
    if (sreq && !sack) begin
      if (!busy) begin busy = 1; ref_v = din; n = n + 1; end
      else if (din !== ref_v) viol = viol + 1;
    end else busy = 0;
  end
  final $display("DIN_STABILITY_VIOLATIONS = %0d (over %0d transfers)", viol, n);
endmodule
