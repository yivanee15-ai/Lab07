// 4-phase handshake synchronizer, clk1 (sclk) -> clk2 (dclk) -- FAST-ACK variant.
// The acknowledge is the (already synchronised) request itself: dack = dreq, so the destination answers
// one dclk cycle earlier on both the rising and the falling phase.  The destination register is loaded one
// cycle later from the source data register, which stays stable until the next transfer is accepted
// (>= one complete 4-phase round trip later), so data stability still holds.
// NOTE: dbusy is not used (back-pressure is not possible with a combinational acknowledge);
//       CLK_2_MODULE consumes every word faster than the handshake can deliver the next one.
// The source control (sreq / source data register) runs on the FALLING edge of sclk: the request is
// raised / dropped half a clk1 cycle earlier than with a rising-edge register (saves 7 ns per phase).
// NOTE: not verified with Jasper CDC (no tool available) -- see docs/results.md.
module Handshake_syn #(parameter WIDTH = 32) (
    input              sclk,
    input              dclk,
    input              rst_n,
    // source side (sclk)
    input              sready,
    input  [WIDTH-1:0] din,
    output             sidle,
    output             flag_handshake_to_clk1,   // carries the synchronised acknowledge (sack)
    input              flag_clk1_to_handshake,
    output             flag_handshake_to_clk2,
    input              flag_clk2_to_handshake,
    // destination side (dclk)
    input              dbusy,
    output reg         dvalid,
    output reg [WIDTH-1:0] dout
);
    wire sdone;
    assign flag_handshake_to_clk1 = sdone;
    assign flag_handshake_to_clk2 = 1'b0;
    reg  sreq;
    wire dreq;
    wire dack;
    wire sack;
    reg  dreq_q;
    reg  [WIDTH-1:0] data;

    NDFF_syn u_req_sync (.D(sreq), .clk(dclk), .rst_n(rst_n), .Q(dreq));
    NDFF_syn u_ack_sync (.D(dack), .clk(sclk), .rst_n(rst_n), .Q(sack));

    assign dack  = dreq;
    assign sidle = ~sreq & ~sack;
    assign sdone = sack;

    always @(negedge sclk or negedge rst_n) begin
        if (!rst_n) begin
            sreq <= 1'b0;
            data <= {WIDTH{1'b0}};
        end else if (sack) begin
            sreq <= 1'b0;
        end else if (sidle & sready) begin
            sreq <= 1'b1;
            data <= din;
        end
    end

    always @(posedge dclk or negedge rst_n) begin
        if (!rst_n) begin
            dreq_q <= 1'b0;
            dvalid <= 1'b0;
            dout   <= {WIDTH{1'b0}};
        end else begin
            dreq_q <= dreq;
            dvalid <= dreq & ~dreq_q;
            if (dreq & ~dreq_q) dout <= data;
        end
    end
endmodule
