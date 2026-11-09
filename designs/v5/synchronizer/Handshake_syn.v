// 4-phase handshake synchronizer, clk1 (sclk) -> clk2 (dclk), structure of Fig.5:
// a source data register (loaded when a transfer is accepted) and a destination register
// (loaded when the destination acknowledges).
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
    reg  dack;
    wire sack;
    reg  [WIDTH-1:0] data;

    NDFF_syn u_req_sync (.D(sreq), .clk(dclk), .rst_n(rst_n), .Q(dreq));
    NDFF_syn u_ack_sync (.D(dack), .clk(sclk), .rst_n(rst_n), .Q(sack));

    assign sidle = ~sreq & ~sack;
    assign sdone = sack;

    always @(posedge sclk or negedge rst_n) begin
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
            dack   <= 1'b0;
            dvalid <= 1'b0;
            dout   <= {WIDTH{1'b0}};
        end else begin
            dvalid <= 1'b0;
            if (dreq & ~dack & ~dbusy) begin
                dack   <= 1'b1;
                dvalid <= 1'b1;
                dout   <= data;
            end else if (~dreq) begin
                dack <= 1'b0;
            end
        end
    end
endmodule
